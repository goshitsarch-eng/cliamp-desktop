package browser

import (
	"fmt"
	"net/url"
	"os/exec"
	"runtime"
	"strings"
	"unicode"
)

// ValidateURL checks that raw is a safe http or https URL suitable for opening
// in a system browser.
func ValidateURL(raw string) (string, error) {
	u := strings.TrimSpace(raw)
	if u == "" || strings.HasPrefix(u, "-") {
		return "", fmt.Errorf("invalid browser URL")
	}
	for _, r := range u {
		if unicode.IsControl(r) || unicode.IsSpace(r) {
			return "", fmt.Errorf("browser URL contains disallowed characters")
		}
	}
	parsed, err := url.Parse(u)
	if err != nil {
		return "", fmt.Errorf("invalid browser URL: %w", err)
	}
	scheme := strings.ToLower(parsed.Scheme)
	if (scheme != "http" && scheme != "https") || parsed.Hostname() == "" || parsed.User != nil {
		return "", fmt.Errorf("browser URL must be http or https with a host and no credentials")
	}
	return parsed.String(), nil
}

// Open tries to open an http(s) URL in the user's default browser.
func Open(raw string) error {
	u, err := ValidateURL(raw)
	if err != nil {
		return err
	}
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", u)
	case "linux":
		cmd = exec.Command("xdg-open", "--", u)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", u)
	default:
		return fmt.Errorf("unsupported platform")
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}
