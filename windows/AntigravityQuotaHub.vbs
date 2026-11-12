Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & Replace(WScript.ScriptFullName, "AntigravityQuotaHub.vbs", "AntigravityQuotaHub.ps1") & """", 0, False
