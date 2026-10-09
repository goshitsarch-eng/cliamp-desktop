package cmd

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"maps"
)

const setupInputLimit = 64 << 10

type setupProvider struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

type setupField struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Help     string `json:"help"`
	Required bool   `json:"required"`
	Secret   bool   `json:"secret"`
	Value    string `json:"value"`
}

type setupOption struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

type setupPicker struct {
	Key     string        `json:"key"`
	Label   string        `json:"label"`
	Options []setupOption `json:"options"`
}

type setupSchema struct {
	OK        bool              `json:"ok"`
	Providers []setupProvider   `json:"providers"`
	Provider  string            `json:"provider,omitempty"`
	Name      string            `json:"name,omitempty"`
	Intro     []string          `json:"intro,omitempty"`
	Picker    *setupPicker      `json:"picker,omitempty"`
	Fields    []setupField      `json:"fields"`
	Values    map[string]string `json:"values"`
}

// SetupSchema describes the interactive wizard's current form for desktop
// clients. Values arrive on stdin, never as command-line arguments. Existing
// configuration and credentials are not read, and secrets are never returned.
func SetupSchema(provider string, input io.Reader, output io.Writer) error {
	values, err := readSetupValues(input)
	if err != nil {
		return writeSetupError(output, err)
	}
	result := setupSchema{OK: true, Fields: []setupField{}, Values: map[string]string{}}
	var selected *providerSpec
	for _, spec := range providers() {
		result.Providers = append(result.Providers, setupProvider{Key: spec.key, Name: spec.name})
		if spec.key == provider {
			selected = &spec
		}
	}
	if provider != "" {
		if selected == nil {
			return writeSetupError(output, errors.New("unknown setup provider"))
		}
		values, err = prepareSetupValues(*selected, values)
		if err != nil {
			return writeSetupError(output, err)
		}
		result.Provider, result.Name, result.Intro = selected.key, selected.name, selected.intro
		if p := selected.picker; p != nil {
			result.Picker = &setupPicker{Key: p.key, Label: p.label}
			for _, option := range p.options {
				result.Picker.Options = append(result.Picker.Options, setupOption{Value: option.value, Label: option.label})
			}
			result.Values[p.key] = values[p.key]
		}
		for _, field := range selected.fields {
			if field.onlyIf != nil && !field.onlyIf(values) {
				continue
			}
			value := ""
			if !field.secret {
				value = values[field.key]
				result.Values[field.key] = value
			}
			result.Fields = append(result.Fields, setupField{
				Key: field.key, Label: field.label, Help: field.help,
				Required: field.required, Secret: field.secret, Value: value,
			})
		}
	}
	return json.NewEncoder(output).Encode(result)
}

// SetupApply validates and saves one provider with the same rules and section
// writer as the interactive wizard. Server error text may contain credentials,
// so only fixed diagnostic messages cross the desktop process boundary.
func SetupApply(provider string, input io.Reader, output io.Writer, verifyConnection bool) error {
	values, err := readSetupValues(input)
	if err != nil {
		return writeSetupError(output, err)
	}
	for _, spec := range providers() {
		if spec.key == provider {
			if err := applySetupValues(spec, values, verifyConnection); err != nil {
				return writeSetupError(output, err)
			}
			return json.NewEncoder(output).Encode(struct {
				OK              bool `json:"ok"`
				RestartRequired bool `json:"restart_required"`
			}{OK: true, RestartRequired: true})
		}
	}
	return writeSetupError(output, errors.New("unknown setup provider"))
}

func applySetupValues(spec providerSpec, values map[string]string, verifyConnection bool) error {
	values, err := prepareSetupValues(spec, values)
	if err != nil {
		return err
	}
	if !verifyConnection {
		// This is the desktop equivalent of the wizard's explicit option to
		// save when a server cannot be reached. All local validation remains.
		spec.validate = nil
	}
	// The model's submission path applies defaults, checks required fields,
	// environment references, URLs and provider limits, and uses SaveSection.
	// Drive its probe synchronously without starting a terminal UI or spinner.
	m := &setupModel{provs: []providerSpec{spec}, pidx: 0, values: values}
	m.refreshVisibleFields()
	m.submitForm()
	if m.stage == stageValidating {
		msg := runValidateCmd(spec, envResolved(m.values))().(validateDoneMsg)
		if msg.err != nil {
			return errors.New("could not verify provider credentials or reach the server")
		}
		m.onValidateDone(nil, msg.found)
	}
	if m.saveFailed != nil {
		return errors.New("could not save provider configuration")
	}
	if m.resultErr != nil {
		return errors.New("provider settings are invalid; check required fields, URLs, environment references, and field limits")
	}
	return nil
}

func prepareSetupValues(spec providerSpec, input map[string]string) (map[string]string, error) {
	allowed := make(map[string]bool, len(spec.fields)+1)
	for _, field := range spec.fields {
		allowed[field.key] = true
	}
	if spec.picker != nil {
		allowed[spec.picker.key] = true
	}
	for key := range input {
		if !allowed[key] {
			return nil, errors.New("unknown provider setup field")
		}
	}
	values := maps.Clone(input)
	if values == nil {
		values = make(map[string]string)
	}
	if picker := spec.picker; picker != nil {
		if values[picker.key] == "" {
			values[picker.key] = picker.options[0].value
		}
		valid := false
		for _, option := range picker.options {
			valid = valid || values[picker.key] == option.value
		}
		if !valid {
			return nil, errors.New("invalid provider setup option")
		}
	}
	visible := make(map[string]bool, len(spec.fields))
	for _, field := range spec.fields {
		if field.onlyIf == nil || field.onlyIf(values) {
			visible[field.key] = true
			if values[field.key] == "" {
				values[field.key] = field.defaultV
			}
		}
	}
	// Switching authentication modes must not leave a hidden token in the
	// connection probe. Some providers have two specs for the same field key.
	for _, field := range spec.fields {
		if !visible[field.key] {
			delete(values, field.key)
		}
	}
	return values, nil
}

func readSetupValues(input io.Reader) (map[string]string, error) {
	if input == nil {
		return map[string]string{}, nil
	}
	data, err := io.ReadAll(io.LimitReader(input, setupInputLimit+1))
	if err != nil {
		return nil, errors.New("could not read provider setup values")
	}
	if len(data) > setupInputLimit {
		return nil, errors.New("provider setup input exceeds 64 KiB")
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return map[string]string{}, nil
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil || raw == nil {
		return nil, errors.New("provider setup input must be a JSON object of strings")
	}
	values := make(map[string]string, len(raw))
	for key, value := range raw {
		var text string
		if len(value) == 0 || value[0] != '"' || json.Unmarshal(value, &text) != nil {
			return nil, errors.New("provider setup input must be a JSON object of strings")
		}
		values[key] = text
	}
	return values, nil
}

func writeSetupError(output io.Writer, err error) error {
	if encodeErr := json.NewEncoder(output).Encode(struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}{Error: err.Error()}); encodeErr != nil {
		return errors.New("could not write provider setup result")
	}
	return err
}
