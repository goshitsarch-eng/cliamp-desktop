//go:build windows

package player

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

var errWindowsAudioTools = errors.New("choose your output in Windows Settings > System > Sound, or install AudioDeviceCmdlets or NirCmd to switch it here")

const listWindowsAudio = `
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ErrorActionPreference = 'Stop'
if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
    $devices = @(Get-AudioDevice -List | Where-Object Type -eq Playback | ForEach-Object {
        @{Name=$_.ID; Description=$_.Name; Active=$_.Default}
    })
} elseif (Get-Command nircmd.exe -CommandType Application -ErrorAction SilentlyContinue) {
    $devices = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render' |
        Where-Object { $_.GetValue('DeviceState') -eq 1 } | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath ($_.PSPath + '\Properties')
            $name = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
            if ($name) { @{Name=$name; Description=$name} }
        })
} else { exit 3 }
ConvertTo-Json -InputObject $devices -Compress
`

const switchWindowsAudio = `
$ErrorActionPreference = 'Stop'
if (Get-Command Set-AudioDevice -ErrorAction SilentlyContinue) {
    Set-AudioDevice -ID $env:CLIAMP_SELECTED_ENDPOINT -DefaultOnly | Out-Null
} elseif (Get-Command nircmd.exe -CommandType Application -ErrorAction SilentlyContinue) {
    & nircmd.exe setdefaultsounddevice $env:CLIAMP_SELECTED_ENDPOINT
    exit $LASTEXITCODE
} else { exit 3 }
`

func windowsAudioCommand(script, device string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	cmd.Env = append(os.Environ(), "CLIAMP_SELECTED_ENDPOINT="+device)
	out, err := cmd.Output()
	var status *exec.ExitError
	if errors.As(err, &status) && status.ExitCode() == 3 {
		return nil, errWindowsAudioTools
	}
	return out, err
}

// ListAudioDevices enumerates playback endpoints using identifiers accepted by
// the installed switcher. A sound controller's hardware ID is not an endpoint.
func ListAudioDevices() ([]AudioDevice, error) {
	out, err := windowsAudioCommand(listWindowsAudio, "")
	if err != nil {
		return nil, fmt.Errorf("audio outputs: %w", err)
	}
	var devices []AudioDevice
	if err := json.Unmarshal(out, &devices); err != nil {
		return nil, fmt.Errorf("read Windows audio outputs: %w", err)
	}
	for i := range devices {
		devices[i].Index = i
	}
	return devices, nil
}

// PrepareAudioDevice uses the Windows system default for new streams.
func PrepareAudioDevice(device string) func() { return func() {} }

// SwitchAudioDevice changes the default Windows playback endpoint. An open
// stream can continue on the previous device until the engine restarts.
func SwitchAudioDevice(device string) error {
	if _, err := windowsAudioCommand(switchWindowsAudio, device); err != nil {
		return fmt.Errorf("switch Windows playback output: %w", err)
	}
	return nil
}
