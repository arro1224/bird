param([string]$Adb,[string]$RunDirectory)
$ErrorActionPreference='Continue'
$deadline=(Get-Date).AddMinutes(8)
$utf8=[Text.UTF8Encoding]::new($false)
# Start-Job does not inherit the parent's UTF-8 console on Chinese Windows.
# adb emits UTF-8 XML; decoding it as CP936 can make the whole hierarchy invalid.
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
$boxNotificationsOpened=$false
$appPairingConfirmed=$false
$boxPairingConfirmed=$false
while ((Get-Date) -lt $deadline) {
    foreach ($serial in 'emulator-5554','emulator-5556') {
        # Once confirmed, stop polling the animated Flutter screen. Its idle
        # wait can otherwise consume the peer's 30-second pairing deadline.
        if (($serial -eq 'emulator-5554' -and $appPairingConfirmed) -or ($serial -eq 'emulator-5556' -and $boxPairingConfirmed)) { continue }
        & $Adb -s $serial shell uiautomator dump /sdcard/ble20-pairing-ui.xml 2>$null | Out-Null
        $raw=(& $Adb -s $serial shell cat /sdcard/ble20-pairing-ui.xml 2>$null) -join "`n"
        try {
            [xml]$ui=$raw
            $hasPairingAction = @($ui.SelectNodes('//node') | Where-Object { $_.GetAttribute('package') -eq 'com.android.systemui' -and $_.GetAttribute('text') -eq 'Pair & connect' }).Count -gt 0
            foreach ($node in $ui.SelectNodes('//node')) {
                $pairingNotification = $serial -eq 'emulator-5556' -and $node.GetAttribute('package') -eq 'com.android.systemui' -and (
                    ($node.GetAttribute('text') -eq 'Pair & connect' -and $node.GetAttribute('resource-id') -eq 'android:id/action0') -or
                    (!$hasPairingAction -and $node.GetAttribute('text') -eq 'Pairing request' -and $node.GetAttribute('resource-id') -eq 'android:id/title'))
                if ($pairingNotification) {
                    $notificationEntry=@{event_type='system_pairing_notification_opened';avd_role='box';occurred_at=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Compress
                    [IO.File]::AppendAllText((Join-Path $RunDirectory 'pairing-ui-actions.jsonl'),$notificationEntry+"`n",$utf8)
                    $notificationBounds=[regex]::Match($node.GetAttribute('bounds'),'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
                    if ($notificationBounds.Success) {
                        & $Adb -s $serial shell input tap (([int]$notificationBounds.Groups[1].Value+[int]$notificationBounds.Groups[3].Value)/2) (([int]$notificationBounds.Groups[2].Value+[int]$notificationBounds.Groups[4].Value)/2) | Out-Null
                    }
                    continue
                }
                if ($node.GetAttribute('resource-id') -notin @('android:id/button1','com.android.settings:id/positive_button') -or $node.GetAttribute('text') -notmatch '^(?i:pair)$') { continue }
                if ($node.GetAttribute('package') -notin @('com.android.settings','com.android.bluetooth')) { continue }
                $bounds=[regex]::Match($node.GetAttribute('bounds'),'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
                if (!$bounds.Success) { continue }
                $x=([int]$bounds.Groups[1].Value+[int]$bounds.Groups[3].Value)/2
                $y=([int]$bounds.Groups[2].Value+[int]$bounds.Groups[4].Value)/2
                & $Adb -s $serial shell input tap ([int]$x) ([int]$y) | Out-Null
                $entry=@{event_type='system_pairing_ui_confirmed';avd_role= $(if ($serial -eq 'emulator-5554') {'app'} else {'box'});occurred_at=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Compress
                [IO.File]::AppendAllText((Join-Path $RunDirectory 'pairing-ui-actions.jsonl'),$entry+"`n",$utf8)
                if ($serial -eq 'emulator-5554') { $appPairingConfirmed=$true } else { $boxPairingConfirmed=$true }
                if ($serial -eq 'emulator-5554' -and !$boxNotificationsOpened) {
                    & $Adb -s emulator-5556 shell cmd statusbar expand-notifications | Out-Null
                    $boxNotificationsOpened=$true
                }
            }
        } catch {
            $failureEntry=@{event_type='system_pairing_ui_read_failed';avd_role=$(if ($serial -eq 'emulator-5554') {'app'} else {'box'});error_type=$_.Exception.GetType().Name;occurred_at=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Compress
            [IO.File]::AppendAllText((Join-Path $RunDirectory 'pairing-ui-actions.jsonl'),$failureEntry+"`n",$utf8)
        }
    }
    Start-Sleep -Milliseconds 500
}
