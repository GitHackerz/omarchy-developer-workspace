import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
 id: root
 property var shell: null
 property var manifest: null
 property string omarchyPath: Quickshell.env("OMARCHY_PATH")
 property bool opened: false
 property string mode: "projects"
 property string filter: "all"
 property string selectedKey: ""
 property var pending: null
 property string notice: ""
 property bool failed: false
 property var snapshot: ({projects: [], services: [], agents: [], dockerAvailable: true, updated: ""})
 readonly property string backend: decodeURIComponent(Qt.resolvedUrl("backend.py").toString().substring(7))
 readonly property color fg: Color.menu.text
 readonly property color bg: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
 readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.045)
 readonly property color accent: "#91b8d5"
 readonly property var rows: {
  var all = mode === "projects" ? snapshot.projects : snapshot.services
  var q = search.text.toLowerCase()
  return all.filter(function(r) {
   return (r.name + " " + r.detail + " " + (r.image || "")).toLowerCase().indexOf(q) !== -1 &&
     (mode === "projects" || filter === "all" || (filter === "containers" && r.kind === "container") || (filter === "ports" && r.kind === "port") || (filter === "stopped" && r.kind === "container" && r.state !== "running"))
  })
 }
 readonly property var selected: {
  for (var i=0;i<rows.length;i++) if (key(rows[i]) === selectedKey) return rows[i]
  return rows.length ? rows[0] : null
 }
 function key(r) { return r.path || r.id || (r.pid + ":" + r.detail) }
 function chooseMode(next) { mode=next; filter="all"; selectedKey=""; search.text=""; notice="" }
 function open(payload) {
  var data={};try { data=JSON.parse(payload || "{}") } catch(e) {}
  chooseMode(data.mode === "services" ? "services" : "projects")
  root.opened=true; pending=null; refresh()
  Qt.callLater(function(){search.forceActiveFocus()})
 }
 function close() { root.opened=false; pending=null }
 function dismiss() { close(); if(shell) shell.hide(manifest ? manifest.id : "developer.workspace") }
 function toggle(payload) { if(opened) dismiss(); else open(payload) }
 function status() { return JSON.stringify({opened:opened,mode:mode,rows:rows.length}) }
 function refresh() { if(!scan.running && !pending && !action.running) scan.running=true }
 function act(kind,value) {
  if(action.running) return
  notice="Working…"; failed=false
  action.command=["python3",backend,"action",kind,value]; action.running=true
 }
 function ask(kind,label,description) {
  var r=selected
  var value=r.kind === "container" ? r.id : JSON.stringify({pid:r.pid,identity:r.identity})
  pending={kind:kind,label:label,name:r.name,description:description,value:value}
 }
 component DevButton: Button {
  id: control
  property bool danger: false
  implicitHeight: 36
  implicitWidth: Math.max(44,caption.implicitWidth+24)
  opacity: enabled ? 1 : 0.4
  contentItem: Text { id:caption; text:control.text; color:control.danger ? "#e5a0a0" : root.fg; font.pixelSize:13; horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter }
  background: Rectangle {
   radius:8
   color:control.down ? "#46546a" : control.highlighted ? "#3c4c60" : control.hovered ? "#3c4654" : root.surface
   border.width:1
   border.color:control.activeFocus ? root.accent : Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.08)
  }
 }
 component Detail: ColumnLayout {
  property string title: ""
  property string value: ""
  spacing:5; Layout.fillWidth:true
  Label { text:parent.title.toUpperCase(); color:root.fg; opacity:0.45; font.pixelSize:10; font.letterSpacing:1.2 }
  Label { text:parent.value; color:root.fg; font.pixelSize:13; wrapMode:Text.WrapAnywhere; Layout.fillWidth:true; textFormat:Text.PlainText }
 }
 Process {
  id:scan; command:["python3",root.backend]
  stdout:StdioCollector { onStreamFinished: {
   try { root.snapshot=JSON.parse(text) } catch(e) { root.notice="Refresh failed. Try again.";root.failed=true }
  } }
 }
 Process {
  id:action
  stdout:StdioCollector { onStreamFinished: {
   try { var result=JSON.parse(text);root.notice=result.message;root.failed=!result.ok }
   catch(e) { root.notice="Action failed. Refresh and try again.";root.failed=true }
  } }
  onExited: function(code,status) { if(code!==0) root.failed=true; Qt.callLater(root.refresh) }
 }
 Timer { interval:5000;repeat:true;running:root.opened && root.mode === "services" && !root.pending;onTriggered:root.refresh() }
 PanelWindow {
  id:panel; visible:root.opened
  anchors { top:true;bottom:true;left:true;right:true }
  color:"transparent";exclusionMode:ExclusionMode.Ignore
  WlrLayershell.namespace:"developer-workspace"
  WlrLayershell.layer:WlrLayer.Overlay
  WlrLayershell.keyboardFocus:WlrKeyboardFocus.Exclusive
  Rectangle { anchors.fill:parent;color:"#85000000" }
  MouseArea { anchors.fill:parent;onClicked: {if(root.pending) root.pending=null;else root.dismiss()} }
  Rectangle {
   id:card;anchors.centerIn:parent
   width:Math.min(1040,panel.width-48);height:Math.min(710,panel.height-72)
   radius:18;color:root.bg;border.width:1;border.color:Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.18)
   MouseArea { anchors.fill:parent }
   ColumnLayout {
    enabled:!root.pending
    anchors.fill:parent;anchors.margins:24;spacing:16
    RowLayout {
     ColumnLayout {
      spacing:4
      Label { text:"Developer Workspace";color:root.fg;font.pixelSize:24;font.bold:true }
      Label { text:root.mode === "projects" ? "Pick a project. Open your tools. Get to work." : "Your local stack, with the controls you need.";color:root.fg;opacity:0.55;font.pixelSize:12 }
     }
     Item { Layout.fillWidth:true }
     Label { text:scan.running ? "Refreshing…" : "Updated "+root.snapshot.updated;color:root.fg;opacity:0.45;font.pixelSize:11 }
     DevButton { text:"↻ Refresh";enabled:!scan.running && !action.running;onClicked:root.refresh() }
     DevButton { text:"×";onClicked:root.dismiss() }
    }
    RowLayout {
     DevButton { text:"Projects  "+root.snapshot.projects.length;highlighted:root.mode === "projects";onClicked:root.chooseMode("projects") }
     DevButton { text:"Services  "+root.snapshot.services.length;highlighted:root.mode === "services";onClicked:root.chooseMode("services") }
     Item { Layout.fillWidth:true }
     Label { visible:root.mode === "services";text:root.snapshot.services.filter(function(r){return r.kind === "container" && r.state === "running"}).length+" running containers";color:"#a1c5ac";font.pixelSize:12 }
    }
    TextField {
     id:search;Layout.fillWidth:true;implicitHeight:42;leftPadding:14;color:root.fg;selectByMouse:true;font.pixelSize:14
     placeholderText:root.mode === "projects" ? "Search projects or folders…" : "Search names, images, or ports…"
     background:Rectangle { radius:9;color:Qt.rgba(0,0,0,0.16);border.width:1;border.color:search.activeFocus ? root.accent : "#47505e" }
     Keys.onEscapePressed: { if(root.pending) root.pending=null;else root.dismiss() }
     Keys.onDownPressed: { list.forceActiveFocus();list.currentIndex=0 }
     onAccepted: { if(root.selected && root.mode === "projects" && !root.pending) root.act("project",root.selected.path) }
    }
    RowLayout {
     visible:root.mode === "services"
     Repeater {
      model:[{id:"all",label:"All"},{id:"containers",label:"Containers"},{id:"ports",label:"Ports"},{id:"stopped",label:"Stopped"}]
      DevButton { required property var modelData;text:modelData.label;highlighted:root.filter === modelData.id;onClicked: {root.filter=modelData.id;root.selectedKey=""} }
     }
     Item { Layout.fillWidth:true }
     Label { text:root.rows.length+" results";color:root.fg;opacity:0.4;font.pixelSize:12 }
    }
    RowLayout {
     Layout.fillWidth:true;Layout.fillHeight:true;spacing:18
     ListView {
      id:list;Layout.preferredWidth:Math.round(card.width*0.43);Layout.fillHeight:true
      clip:true;spacing:7;model:root.rows;currentIndex:-1
      ScrollBar.vertical:ScrollBar {}
      Keys.onEscapePressed:root.dismiss()
      onCurrentIndexChanged: {if(currentIndex>=0 && currentIndex<root.rows.length) root.selectedKey=root.key(root.rows[currentIndex])}
      Keys.onReturnPressed: {if(root.selected && root.mode === "projects") root.act("project",root.selected.path)}
      delegate:Rectangle {
       required property var modelData
       required property int index
       readonly property bool chosen:root.selected && root.key(root.selected) === root.key(modelData)
       width:list.width;height:72;radius:10
       color:chosen ? "#3c4b5e" : hover.hovered ? Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.07) : root.surface
       border.width:chosen ? 1 : 0;border.color:"#647f9a"
       HoverHandler { id:hover }
       MouseArea { anchors.fill:parent;onClicked: {root.selectedKey=root.key(modelData);list.currentIndex=index} }
       RowLayout {
        anchors.fill:parent;anchors.margins:12;spacing:10
        Rectangle { width:7;height:7;radius:4;color:modelData.kind === "project" ? root.accent : modelData.state === "running" || modelData.state === "listening" ? "#9ac3a3" : "#858a96" }
        ColumnLayout {
         Layout.fillWidth:true;spacing:5
         Label { text:modelData.name;color:root.fg;font.pixelSize:14;font.bold:chosen;Layout.fillWidth:true;elide:Text.ElideRight;textFormat:Text.PlainText }
         Label { text:modelData.kind === "project" ? modelData.detail : modelData.kind === "container" ? modelData.state+" · "+modelData.image : modelData.detail;color:root.fg;opacity:0.5;font.pixelSize:11;Layout.fillWidth:true;elide:Text.ElideMiddle;textFormat:Text.PlainText }
        }
       }
      }
      Label { anchors.centerIn:parent;visible:root.rows.length === 0;text:scan.running ? "Loading…" : "No matches";color:root.fg;opacity:0.5 }
     }
     Rectangle {
      Layout.fillWidth:true;Layout.fillHeight:true;radius:12;color:root.surface
      ScrollView {
       anchors.fill:parent;anchors.margins:20;clip:true
       contentWidth:availableWidth
       ColumnLayout {
        width:parent.width;spacing:16
        Label { text:root.selected ? root.selected.kind === "project" ? "PROJECT" : root.selected.kind === "container" ? "CONTAINER" : "LISTENING PROCESS" : "SELECT AN ITEM";color:root.accent;font.pixelSize:10;font.letterSpacing:1.5 }
        Label { text:root.selected ? root.selected.name : "Nothing selected";color:root.fg;font.pixelSize:22;font.bold:true;Layout.fillWidth:true;wrapMode:Text.WrapAnywhere;textFormat:Text.PlainText }
        Detail { title:root.mode === "projects" ? "Folder" : "Status / address";value:root.selected ? root.selected.path || root.selected.detail : "" }
        Detail { visible:root.selected && root.selected.kind === "container";title:"Image";value:root.selected ? root.selected.image || "" : "" }
        Detail { visible:root.selected && root.selected.kind === "port" && !!root.selected.pid;title:"Process ID";value:root.selected ? root.selected.pid || "" : "" }
        Rectangle { Layout.fillWidth:true;height:1;color:Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.1) }
        Flow {
         visible:root.mode === "projects" && !!root.selected
         Layout.fillWidth:true;spacing:8
         DevButton { text:"Open workspace";highlighted:true;enabled:!action.running;onClicked:root.act("project",root.selected.path) }
         DevButton { text:"Editor";enabled:!action.running;onClicked:root.act("editor",root.selected.path) }
         DevButton { text:"Terminal";enabled:!action.running;onClicked:root.act("terminal",root.selected.path) }
         DevButton { text:"Files";enabled:!action.running;onClicked:root.act("files",root.selected.path) }
         DevButton { text:"Copy path";onClicked:root.act("copy",root.selected.path) }
        }
        ColumnLayout {
         visible:root.mode === "projects" && !!root.selected
         Layout.fillWidth:true;spacing:8
         Label { text:"OPEN WITH AI";color:root.accent;font.pixelSize:10;font.letterSpacing:1.2 }
         Label { text:"Starts an interactive session in this project.";color:root.fg;opacity:0.55;font.pixelSize:12;wrapMode:Text.WordWrap;Layout.fillWidth:true }
         ComboBox {
          id:agent;Layout.fillWidth:true;implicitHeight:40
          model:root.snapshot.agents;textRole:"name"
          contentItem:Text { text:agent.currentText;color:root.fg;font.pixelSize:13;verticalAlignment:Text.AlignVCenter;leftPadding:12 }
          background:Rectangle { radius:8;color:"#343e4c";border.width:1;border.color:"#536479" }
          delegate:ItemDelegate {
           required property var modelData
           width:agent.width;text:modelData.name+(modelData.available ? "" : " · not installed");enabled:modelData.available
           contentItem:Text { text:parent.text;color:root.fg;font.pixelSize:13 }
           background:Rectangle { color:parent.highlighted ? "#465870" : "#303946" }
          }
          popup:Popup {
           y:agent.height+4;width:agent.width;padding:4
           background:Rectangle { radius:8;color:"#303946";border.width:1;border.color:"#59697e" }
           contentItem:ListView { implicitHeight:contentHeight;model:agent.popup.visible ? agent.delegateModel : null;currentIndex:agent.highlightedIndex;clip:true }
          }
         }
         DevButton { text:"Launch "+agent.currentText;highlighted:true;Layout.fillWidth:true;enabled:!action.running && agent.currentIndex>=0 && !!root.snapshot.agents[agent.currentIndex] && root.snapshot.agents[agent.currentIndex].available;onClicked:root.act("ai-"+root.snapshot.agents[agent.currentIndex].id,root.selected.path) }
        }
        Flow {
         visible:root.selected && root.selected.kind === "container"
         Layout.fillWidth:true;spacing:8
         DevButton { text:"Live logs";enabled:!action.running;onClicked:root.act("logs",root.selected.id) }
         DevButton { text:"Inspect";enabled:!action.running;onClicked:root.act("inspect",root.selected.id) }
         DevButton { text:"Start";visible:root.selected && ["exited","created"].indexOf(root.selected.state)!==-1;enabled:!action.running;onClicked:root.act("start",root.selected.id) }
         DevButton { text:"Restart";visible:root.selected && root.selected.state === "running";enabled:!action.running;onClicked:root.ask("restart","Restart container","This interrupts connections while the container restarts.") }
         DevButton { text:"Stop";danger:true;visible:root.selected && root.selected.state === "running";enabled:!action.running;onClicked:root.ask("stop","Stop container","This stops the container and disconnects its clients.") }
         DevButton { text:"Remove";danger:true;visible:root.selected && ["exited","created","dead"].indexOf(root.selected.state)!==-1;enabled:!action.running;onClicked:root.ask("remove","Remove container","Removes this stopped container and its writable layer. Docker volumes are kept.") }
         DevButton { text:"Copy name";onClicked:root.act("copy",root.selected.name) }
        }
        Flow {
         visible:root.selected && root.selected.kind === "port"
         Layout.fillWidth:true;spacing:8
         DevButton { text:"Open browser";visible:root.selected && !!root.selected.url;onClicked:root.act("browser",root.selected.url) }
         DevButton { text:"Copy address";onClicked:root.act("copy",root.selected.url || "localhost:"+root.selected.port) }
         DevButton { text:"Stop process";danger:true;visible:root.selected && !!root.selected.canStop;enabled:!action.running;onClicked:root.ask("terminate","Stop process","Requests a graceful exit for this project process. All ports owned by it will close.") }
         DevButton { text:"Force kill";danger:true;visible:root.selected && !!root.selected.canStop;enabled:!action.running;onClicked:root.ask("kill","Force kill process","Immediately kills this project process. Unsaved work in the process may be lost.") }
        }
        Label { visible:root.selected && root.selected.kind === "port" && !root.selected.canStop;text:"Process controls are available for your own processes running inside your project folders.";color:root.fg;opacity:0.45;font.pixelSize:12;wrapMode:Text.WordWrap;Layout.fillWidth:true }
       }
      }
     }
    }
    Label { visible:root.notice!=="" || (root.mode === "services" && !root.snapshot.dockerAvailable);text:root.notice || "Docker unavailable · listening ports are still shown";color:root.failed ? "#e5a0a0" : "#a1c5ac";font.pixelSize:12;wrapMode:Text.WordWrap;Layout.fillWidth:true }
    Label { text:"↑ ↓ select   ·   Enter opens workspace   ·   Esc closes";color:root.fg;opacity:0.35;font.pixelSize:11 }
   }
   Rectangle {
    visible:!!root.pending;anchors.fill:parent;color:"#b0000000";radius:18;z:10
    focus:visible
    onVisibleChanged: { if(visible) forceActiveFocus();else if(root.opened) search.forceActiveFocus() }
    Keys.onEscapePressed:root.pending=null
    Keys.onReturnPressed:function(event){event.accepted=true}
    MouseArea { anchors.fill:parent }
    Rectangle {
     anchors.centerIn:parent;width:Math.min(460,card.width-60);height:230;radius:14;color:root.bg;border.width:1;border.color:"#8c6670"
     ColumnLayout {
      anchors.fill:parent;anchors.margins:22;spacing:12
      Label { text:root.pending ? root.pending.label+"?" : "";color:root.fg;font.bold:true;font.pixelSize:20 }
      Label { text:root.pending ? root.pending.name : "";color:root.accent;Layout.fillWidth:true;elide:Text.ElideRight;textFormat:Text.PlainText }
      Label { text:root.pending ? root.pending.description : "";color:root.fg;opacity:0.7;wrapMode:Text.WordWrap;Layout.fillWidth:true }
      Item { Layout.fillHeight:true }
      RowLayout {
       Item { Layout.fillWidth:true }
       DevButton { text:"Cancel";onClicked:root.pending=null }
       DevButton { text:root.pending ? root.pending.label : "Confirm";danger:true;onClicked: {var p=root.pending;root.pending=null;root.act(p.kind,p.value)} }
      }
     }
    }
   }
  }
 }
}
