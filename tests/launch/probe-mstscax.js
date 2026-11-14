// Probe: create the Microsoft RDP ActiveX control by ProgID and read version info.
// Run: wine cscript //nologo probe-mstscax.js
var progids = ["MsTscAx.MsTscAx", "MsTscAx.MsTscAx.2", "MsRdpClient.MsRdpClient", "MsTscAx.MsTscAx.11"];
for (var i = 0; i < progids.length; i++) {
  try {
    var o = new ActiveXObject(progids[i]);
    var v = "?"; try { v = o.Version; } catch (e) { v = "Version threw " + e.number; }
    WScript.Echo("OK " + progids[i] + " Version=" + v);
  } catch (e) {
    WScript.Echo("FAIL " + progids[i] + " 0x" + (e.number >>> 0).toString(16) + " " + e.description);
  }
}
