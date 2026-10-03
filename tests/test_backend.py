import importlib.util
import json
import signal
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backend', Path(__file__).resolve().parents[1] / 'plugin/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class BackendTests(unittest.TestCase):
    def test_discovery_skips_dependencies_and_keeps_monorepos_together(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            repo = root / 'project with spaces'
            repo.mkdir()
            (repo / 'package.json').write_text('{}')
            nested = repo / 'apps/web'
            nested.mkdir(parents=True)
            (nested / 'package.json').write_text('{}')
            with patch.object(backend, 'settings', return_value={'projectRoots': [folder], 'maxDepth': 4}):
                self.assertEqual([p['path'] for p in backend.projects()], [str(repo)])

    def test_ai_agents_receive_project_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(backend, 'projects', return_value=[{'path': folder}]), patch.object(backend, 'terminal') as terminal, patch.object(backend.shutil, 'which', return_value='/bin/agent'):
                for tool in ('codex', 'agy', 'claude'):
                    backend.action('ai-' + tool, folder)
                    terminal.assert_called_with(Path(folder), ['/bin/agent'])

    def test_unknown_project_is_rejected(self):
        with patch.object(backend, 'projects', return_value=[]), patch.object(backend, 'launch') as launch:
            with self.assertRaises(ValueError):
                backend.action('terminal', '/tmp')
            launch.assert_not_called()

    def test_ghostty_disables_single_instance_and_sets_directory(self):
        with patch.object(backend.shutil, 'which', return_value='/usr/bin/ghostty'), patch.object(backend, 'launch') as launch:
            backend.terminal('/tmp', ['codex'])
            self.assertEqual(launch.call_args.args[0], ['uwsm-app', '--', 'ghostty', '--gtk-single-instance=false', '--working-directory=/tmp', '-e', 'codex'])

    def test_fallback_enters_directory_inside_terminal(self):
        with patch.object(backend.shutil, 'which', return_value=None), patch.object(backend, 'launch') as launch:
            backend.terminal('/tmp', ['claude'])
            args = launch.call_args.args[0]
            self.assertIn('cd "$1" || exit; shift; exec "$@"', args)
            self.assertEqual(args[-2:], ['/tmp', 'claude'])

    def test_running_container_cannot_be_removed(self):
        with patch.object(backend, 'run', return_value='running'), patch.object(backend, 'checked') as checked:
            with self.assertRaises(ValueError):
                backend.action('remove', 'a' * 12)
            checked.assert_not_called()

    def test_removal_keeps_volumes_and_never_forces(self):
        with patch.object(backend, 'run', return_value='exited'), patch.object(backend, 'checked') as checked:
            backend.action('remove', 'a' * 12)
            checked.assert_called_once_with(['docker', 'rm', 'a' * 12])

    def test_invalid_container_id_is_rejected(self):
        with patch.object(backend, 'checked') as checked:
            with self.assertRaises(ValueError):
                backend.action('stop', 'abc; touch /tmp/injected')
            checked.assert_not_called()

    def test_process_uses_pidfd_and_graceful_signal(self):
        rows = [{'pid': '42', 'canStop': True, 'identity': '100'}]
        with patch.object(backend, 'services', return_value={'rows': rows}), patch.object(backend.os, 'pidfd_open', return_value=99), patch.object(backend.os, 'close') as close, patch.object(backend, 'process_identity', return_value='100'), patch.object(backend.signal, 'pidfd_send_signal') as send:
            backend.action('terminate', json.dumps({'pid': '42', 'identity': '100'}))
            send.assert_called_once_with(99, signal.SIGTERM)
            close.assert_called_once_with(99)

    def test_pid_identity_change_is_rejected(self):
        rows = [{'pid': '42', 'canStop': True, 'identity': '100'}]
        with patch.object(backend, 'services', return_value={'rows': rows}), patch.object(backend.os, 'pidfd_open', return_value=99), patch.object(backend.os, 'close') as close, patch.object(backend, 'process_identity', return_value='101'), patch.object(backend.signal, 'pidfd_send_signal') as send:
            with self.assertRaises(ValueError):
                backend.action('kill', json.dumps({'pid': '42', 'identity': '100'}))
            send.assert_not_called()
            close.assert_called_once_with(99)

    def test_system_process_is_rejected(self):
        with patch.object(backend, 'services', return_value={'rows': [{'pid': '42', 'canStop': False, 'identity': '100'}]}), patch.object(backend.os, 'pidfd_open') as opened:
            with self.assertRaises(ValueError):
                backend.action('kill', json.dumps({'pid': '42', 'identity': '100'}))
            opened.assert_not_called()

    def test_docker_unavailable_keeps_empty_service_list(self):
        with patch.object(backend, 'run', return_value=''):
            self.assertEqual(backend.services(), {'rows': [], 'dockerAvailable': False})


if __name__ == '__main__':
    unittest.main()
