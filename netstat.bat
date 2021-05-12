@echo off
pushd %~dp0
set script="%~dp0\netstat.ps1"
echo while($true) > %script%
echo { >> %script%
echo $now = powershell get-date -format "{yyyy-MM-dd_HHmmss}" >> %script%
echo echo $now >> %script%
echo $job = Start-Job -ScriptBlock { >> %script%
echo netstat >> %script%
echo sleep 15 >> %script%
echo } >> %script%
@echo:  >> %script%
echo # Wait for job to complete with timeout (in seconds) >> %script%
echo $job ^| Wait-Job -Timeout 10 >> %script%
@echo:  >> %script%
echo Receive-Job -Job $job ^| Out-File -FilePath .\netstat_$now.txt >> %script%
@echo:  >> %script%
echo # Check to see if any jobs are still running and stop them >> %script%
echo $job ^| Where-Object {$_.State -ne "Completed"} ^| Stop-Job >> %script%
echo } >> %script%
powershell -noprofile -nologo -executionpolicy bypass -File %script%
pause