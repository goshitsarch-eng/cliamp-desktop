package pluginmgr

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/bjarneo/cliamp/config"
	"github.com/bjarneo/cliamp/internal/appdir"
	"github.com/bjarneo/cliamp/internal/fileutil"
	"github.com/bjarneo/cliamp/internal/plugintrust"
	"github.com/bjarneo/cliamp/luaplugin"
)

const implicitPluginAccess = "Unrestricted file reads; allowlisted file writes; public HTTP. Declared permissions may additionally permit playback control, process execution, or keybindings."

type desktopRequest struct {
	Source      string            `json:"source"`
	Name        string            `json:"name"`
	Token       string            `json:"token"`
	SHA256      string            `json:"sha256"`
	Permissions []string          `json:"permissions"`
	Values      map[string]string `json:"values"`
}

type desktopReview struct {
	Token          string    `json:"token"`
	Action         string    `json:"action"`
	Name           string    `json:"name"`
	Source         string    `json:"source"`
	SHA256         string    `json:"sha256"`
	Permissions    []string  `json:"permissions"`
	ImplicitAccess string    `json:"implicit_access"`
	Code           string    `json:"code"`
	Created        time.Time `json:"created"`
}

type desktopPlugin struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Version     string   `json:"version"`
	Type        string   `json:"type"`
	Trust       string   `json:"trust"`
	Permissions []string `json:"permissions"`
	Enabled     bool     `json:"enabled"`
	ConfigKeys  []string `json:"config_keys"`
}

// Desktop serves bounded JSON requests for plugin management. Preparing or
// reviewing a plugin never installs or approves it. A subsequent apply/trust
// must echo the exact source, hash and permissions shown in that review.
func Desktop(action string, input io.Reader, output io.Writer) error {
	request, err := readDesktopRequest(input)
	if err == nil {
		var result map[string]any
		result, err = desktopAction(action, request)
		if err == nil {
			result["ok"] = true
			return json.NewEncoder(output).Encode(result)
		}
	}
	if encodeErr := json.NewEncoder(output).Encode(map[string]any{"ok": false, "error": err.Error()}); encodeErr != nil {
		return errors.New("could not write plugin management response")
	}
	return err
}

func readDesktopRequest(input io.Reader) (desktopRequest, error) {
	var request desktopRequest
	if input == nil {
		return request, nil
	}
	data, err := io.ReadAll(io.LimitReader(input, 64<<10+1))
	if err != nil || len(data) > 64<<10 {
		return request, errors.New("could not read plugin request within 64 KiB limit")
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return request, nil
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return request, errors.New("invalid plugin management request")
	}
	if decoder.Decode(new(any)) != io.EOF {
		return request, errors.New("provide one plugin management request")
	}
	return request, nil
}

func desktopAction(action string, request desktopRequest) (map[string]any, error) {
	dir, err := appdir.PluginDir()
	if err != nil {
		return nil, errors.New("could not locate plugin directory")
	}
	switch action {
	case "list":
		return desktopList(dir)
	case "prepare":
		urls, name, err := resolveSource(request.Source)
		if err != nil || !validDesktopPluginName(name) {
			return nil, errors.New("invalid plugin source")
		}
		if err := ensurePluginAbsent(dir, name); err != nil {
			return nil, err
		}
		if _, err := plugintrust.Load(dir); err != nil {
			return nil, errors.New("plugin trust manifest could not be read")
		}
		var body []byte
		for _, url := range urls {
			if data, err := download(url); err == nil {
				body = data
				break
			}
		}
		if body == nil {
			return nil, errors.New("could not download plugin source")
		}
		review, err := saveDesktopReview(dir, "install", name, request.Source, body)
		if err != nil {
			return nil, err
		}
		return map[string]any{"review": review}, nil
	case "review":
		path, err := installedPluginPath(dir, request.Name)
		if err != nil {
			return nil, err
		}
		body, err := readPluginSource(path)
		if err != nil {
			return nil, err
		}
		review, err := saveDesktopReview(dir, "trust", request.Name, path, body)
		if err != nil {
			return nil, err
		}
		return map[string]any{"review": review}, nil
	case "apply", "trust":
		if err := approveDesktopReview(dir, action, request); err != nil {
			return nil, err
		}
		return map[string]any{"restart_required": true}, nil
	case "remove":
		path, err := installedPluginPath(dir, request.Name)
		if err != nil {
			return nil, err
		}
		if _, err := plugintrust.Load(dir); err != nil {
			return nil, errors.New("plugin trust manifest could not be read")
		}
		if filepath.Base(path) == "init.lua" && filepath.Base(filepath.Dir(path)) == request.Name {
			err = os.RemoveAll(filepath.Dir(path))
		} else {
			err = os.Remove(path)
		}
		if err != nil {
			return nil, errors.New("could not remove plugin")
		}
		if err := plugintrust.Revoke(dir, request.Name); err != nil {
			return nil, errors.New("could not revoke removed plugin approval")
		}
		return map[string]any{"restart_required": true}, nil
	case "configure":
		if _, err := installedPluginPath(dir, request.Name); err != nil {
			return nil, err
		}
		var values []config.Setting
		for key, value := range request.Values {
			if key == "" || strings.ContainsAny(key, " \t\r\n[]=.\x00") || strings.ContainsAny(value, "\r\n\x00") {
				return nil, errors.New("invalid plugin configuration field")
			}
			encoded := config.QuoteString(value)
			if key == "enabled" {
				if value != "true" && value != "false" {
					return nil, errors.New("enabled must be true or false")
				}
				encoded = value
			}
			values = append(values, config.Setting{Section: "plugins." + request.Name, Key: key, Value: encoded})
		}
		slices.SortFunc(values, func(a, b config.Setting) int { return strings.Compare(a.Key, b.Key) })
		if request.Values["enabled"] == "true" {
			cfg, err := config.Load()
			if err != nil {
				return nil, errors.New("could not read plugin configuration")
			}
			var keep []string
			for _, name := range strings.Split(cfg.Plugins[""]["disabled"], ",") {
				if name = strings.TrimSpace(name); name != "" && name != request.Name {
					keep = append(keep, config.QuoteString(name))
				}
			}
			values = append(values, config.Setting{Section: "plugins", Key: "disabled", Value: "[" + strings.Join(keep, ", ") + "]"})
		}
		if err := config.SaveSettings(values); err != nil {
			return nil, errors.New("could not save plugin configuration")
		}
		return map[string]any{"restart_required": true}, nil
	default:
		return nil, errors.New("unknown plugin management action")
	}
}

func desktopList(dir string) (map[string]any, error) {
	plugins, err := scanPlugins(dir)
	if err != nil && !os.IsNotExist(err) {
		return nil, errors.New("could not read installed plugins")
	}
	manifest, trustErr := plugintrust.Load(dir)
	if trustErr != nil {
		manifest = plugintrust.Manifest{}
	}
	cfg, err := config.Load()
	if err != nil {
		return nil, errors.New("could not read plugin settings")
	}
	list := make([]desktopPlugin, 0, len(plugins))
	for _, plugin := range plugins {
		trust := "untrusted"
		switch err := plugintrust.Verify(manifest, plugin.id, plugin.path); {
		case err == nil:
			trust = "trusted"
		case errors.Is(err, plugintrust.ErrHashMismatch):
			trust = "changed"
		}
		if plugin.err != nil {
			trust = "invalid"
		}
		enabled := cfg.Plugins[plugin.id]["enabled"] != "false"
		for _, disabled := range strings.Split(cfg.Plugins[""]["disabled"], ",") {
			if strings.TrimSpace(disabled) == plugin.id {
				enabled = false
			}
		}
		keys := make([]string, 0, len(cfg.Plugins[plugin.id]))
		for key := range cfg.Plugins[plugin.id] {
			if key != "enabled" {
				keys = append(keys, key)
			}
		}
		slices.Sort(keys)
		list = append(list, desktopPlugin{ID: plugin.id, Name: printable(plugin.Name), Description: printable(plugin.Description), Version: printable(plugin.Version), Type: plugin.Type, Trust: trust, Permissions: append([]string{}, plugin.Permissions...), Enabled: enabled, ConfigKeys: keys})
	}
	result := map[string]any{"plugins": list}
	if trustErr != nil {
		result["warning"] = "Plugin trust manifest is unreadable; plugins remain untrusted."
	}
	return result, nil
}

func installedPluginPath(dir, name string) (string, error) {
	if !validDesktopPluginName(name) {
		return "", errors.New("invalid plugin name")
	}
	files, err := luaplugin.Discover(dir)
	if err != nil {
		return "", errors.New("could not find installed plugin")
	}
	for _, file := range files {
		if file.Name == name {
			return file.Path, nil
		}
	}
	return "", errors.New("plugin is not installed")
}

func validDesktopPluginName(name string) bool {
	return validateName(name) == nil && !strings.ContainsAny(name, "\r\n[]=\x00")
}

func ensurePluginAbsent(dir, name string) error {
	for _, path := range []string{filepath.Join(dir, name+".lua"), filepath.Join(dir, name)} {
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			return errors.New("plugin already exists; remove it before installing")
		}
	}
	return nil
}

func readPluginSource(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("could not read plugin source")
	}
	defer file.Close()
	body, err := io.ReadAll(io.LimitReader(file, maxPluginSize+1))
	if err != nil || len(body) == 0 || len(body) > maxPluginSize {
		return nil, errors.New("plugin source must be between 1 byte and 1 MiB")
	}
	return body, nil
}

func reviewDirectory(dir string) string { return filepath.Join(filepath.Dir(dir), ".plugin-reviews") }

func saveDesktopReview(dir, action, name, source string, body []byte) (desktopReview, error) {
	var review desktopReview
	metadata, err := luaplugin.ReadMetadata(string(body))
	if err != nil || metadata.Type == "" {
		return review, errors.New("plugin metadata is invalid")
	}
	var nonce [32]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return review, errors.New("could not create plugin review")
	}
	review = desktopReview{Token: hex.EncodeToString(nonce[:]), Action: action, Name: name, Source: source, SHA256: plugintrust.Hash(body), Permissions: append([]string{}, metadata.Permissions...), ImplicitAccess: implicitPluginAccess, Code: string(body), Created: time.Now()}
	path := reviewDirectory(dir)
	if err := os.MkdirAll(path, 0o700); err != nil {
		return review, errors.New("could not store plugin review")
	}
	data, err := json.Marshal(review)
	if err != nil {
		return review, errors.New("could not encode plugin review")
	}
	if err := fileutil.WriteFileAtomic(filepath.Join(path, review.Token+".json"), data, 0o600); err != nil {
		return review, errors.New("could not store plugin review")
	}
	return review, nil
}

func approveDesktopReview(dir, action string, request desktopRequest) error {
	nonce, err := hex.DecodeString(request.Token)
	if err != nil || len(nonce) != 32 {
		return errors.New("a valid plugin review is required")
	}
	path := filepath.Join(reviewDirectory(dir), request.Token+".json")
	file, err := os.Open(path)
	if err != nil {
		return errors.New("plugin review is missing; review the plugin again")
	}
	data, err := io.ReadAll(io.LimitReader(file, 2*maxPluginSize+1))
	file.Close()
	if err != nil || len(data) > 2*maxPluginSize {
		return errors.New("could not read plugin review")
	}
	var review desktopReview
	if json.Unmarshal(data, &review) != nil || time.Since(review.Created) > 24*time.Hour || time.Since(review.Created) < 0 {
		return errors.New("plugin review expired; review the plugin again")
	}
	wanted := "install"
	if action == "trust" {
		wanted = "trust"
	}
	if review.Action != wanted || review.Token != request.Token || review.Source != request.Source || review.SHA256 != request.SHA256 || !slices.Equal(review.Permissions, request.Permissions) {
		return errors.New("approval must match the reviewed source, hash, and permissions")
	}
	if !validDesktopPluginName(review.Name) || plugintrust.Hash([]byte(review.Code)) != review.SHA256 {
		return errors.New("review content changed; review the plugin again")
	}
	metadata, err := luaplugin.ReadMetadata(review.Code)
	if err != nil || !slices.Equal(metadata.Permissions, review.Permissions) {
		return errors.New("review permissions changed; review the plugin again")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return errors.New("could not create plugin directory")
	}
	unlock, err := fileutil.LockFile(filepath.Join(dir, ".desktop-management.lock"))
	if err != nil {
		return errors.New("could not lock plugin directory")
	}
	defer unlock()
	if _, err := plugintrust.Load(dir); err != nil {
		return errors.New("plugin trust manifest could not be read")
	}
	destination := ""
	if action == "trust" {
		destination, err = installedPluginPath(dir, review.Name)
		if err != nil {
			return err
		}
		if destination != review.Source {
			return errors.New("installed plugin path changed; review the plugin again")
		}
	} else {
		if err := ensurePluginAbsent(dir, review.Name); err != nil {
			return err
		}
		destination = filepath.Join(dir, review.Name+".lua")
		file, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err != nil {
			return errors.New("could not create plugin file")
		}
		_, writeErr := file.WriteString(review.Code)
		closeErr := file.Close()
		if writeErr != nil || closeErr != nil {
			os.Remove(destination)
			return errors.New("could not write plugin file")
		}
	}
	if err := plugintrust.ApproveHash(dir, review.Name, destination, review.SHA256, review.Permissions); err != nil {
		if action == "apply" {
			os.Remove(destination)
		}
		return errors.New("plugin content changed or trust could not be recorded; review the plugin again")
	}
	_ = os.Remove(path)
	return nil
}
