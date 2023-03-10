package main

import (
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"

	// embed the psql driver in order to use it directly (no need to have it installed)
	_ "github.com/volatiletech/sqlboiler/v4/drivers/sqlboiler-psql/driver"

	"github.com/meitner-se/meitnercli/boilerconfig"

	"github.com/ardanlabs/conf/v3"
	"github.com/ardanlabs/conf/v3/yaml"
	"github.com/friendsofgo/errors"
	"github.com/meitner-se/oto/parser"
	"github.com/meitner-se/oto/render"
	"github.com/pressly/goose/v3"

	_ "github.com/lib/pq" // Import the postgres driver
)

const (
	boilerConfigFile = "sqlboiler.toml"
	boilerDriver     = "psql"
	configFile       = "meitnercli.yml"
	namespace        = "meitnercli"

	argBootstrap = "bootstrap"
	argGenerate  = "generate"
	argWipe      = "wipe"
)

var argsWithHelp = []string{
	argBootstrap + " (bootstrap the tables in the database, which are used for generation)",
	argGenerate + " (generate files)",
	argWipe + " (wipe files)",
}

// Version is set during build.
var Version = "dev"

func main() {
	err := run(context.Background(), os.Args)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "failed to run program: %v\n", err)
		os.Exit(1)
	}
}

type config struct {
	conf.Version
	Args    conf.Args
	Path    string `conf:"flag:config,env:CONFIG"`
	Layer   string `conf:"help:generate or wipe a specific layer"`
	Service string `conf:"help:generate or wipe a specific service"`
	Stubs   bool   `conf:"help:generate or wipe stubs,default:false"`
	DB      struct {
		Name     string `conf:"help:name of the database, default:meitner-dev"`
		User     string `conf:"help:user of the database, default:meitner"`
		Password string `conf:"help:password of the user, default:meitner"`
		Host     string `conf:"help:hostname of the database, default:localhost"`
		Port     int    `conf:"help:port of the database, default:5432"`
		SSLMode  string `conf:"help:ssl mode for the database, default:disable"`
	}
	Go struct {
		RootDir       string `conf:"help:root directory for the go server, default:./" yaml:"root_dir"`
		ServiceDir    string `conf:"help:where the services should be generated, default:./internal/services" yaml:"service_dir"`
		ServiceAPIDir string `conf:"help:where the api definitions should be generated, default:./api/services" yaml:"service_api_dir"`
		ModuleName    string `conf:"help:module name of the go server, default:meitner" yaml:"module_name"`
		Packages      struct {
			API      string `conf:"help:name of the api package which should be used in generation, default:meitner/pkg/api"`
			Audit    string `conf:"help:name of the audit package which should be used in generation, default:meitner/pkg/audit"`
			Auth     string `conf:"help:name of the auth package which should be used in generation, default:meitner/pkg/auth"`
			Database string `conf:"help:name of the database package which should be used in generation, default:meitner/pkg/database"`
			Errors   string `conf:"help:name of the errors package which should be used in generation, default:meitner/pkg/errors"`
			Logger   string `conf:"help:name of the logger package which should be used in generation, default:meitner/pkg/logger"`
			Slice    string `conf:"help:name of the slice package which should be used in generation, default:meitner/pkg/slice"`
			Sort     string `conf:"help:name fo the sort package which should be used in generation, default:meitner/pkg/sort"`
			Types    string `conf:"help:name of the types package which should be used in generation, default:meitner/pkg/types"`
			Valid    string `conf:"help:name of the valid package which should be used to add validations in generation, default:meitner/pkg/valid"`
		}
	}
	OtoSkipBackend     bool `conf:"help:skip backend oto templates, default:false" yaml:"oto_skip_backend_only"`
	OtoSkipAfterScript bool `conf:"help:skip after script oto, default:false" yaml:"oto_skip_after_script"`
	Oto                []struct {
		Template               string         `conf:""`
		OutputFile             string         `conf:"" yaml:"output_file"`
		PackageName            string         `conf:"" yaml:"package_name"`
		Definition             string         `conf:""`
		Backend                bool           `conf:""`
		AddReturnObjectMethods bool           `conf:"" yaml:"add_return_object_methods"`
		Ignore                 []string       `conf:""`
		Params                 map[string]any `conf:""`
		AfterScript            []string       `conf:"" yaml:"after_script"`
	}
}

func run(_ context.Context, args []string) error {
	cfg := config{
		Version: conf.Version{
			Build: Version,
			Desc:  fmt.Sprintf("%s is a tool which wraps sqlboiler to generate code from the database and oto to generate code from API-definitions", namespace),
		},
	}

	var configParsers []conf.Parsers
	foundConfigFile := findConfigFile()
	if foundConfigFile != "" {
		// if we found config file it might not be in the same working directory
		// all directory in config file usually assumes relative paths from the config directory,
		// so we should switch our working directory to be in the config file directory.
		err := os.Chdir(filepath.Dir(foundConfigFile))
		if err != nil {
			return err
		}
		configBytes, err := os.ReadFile(foundConfigFile)
		if err != nil {
			return err
		}
		configParsers = append(configParsers, yaml.WithData(configBytes))
	}

	parseString, err := conf.Parse(namespace, &cfg, configParsers...)
	if err != nil {
		if errors.Is(err, conf.ErrHelpWanted) {
			fmt.Println(parseString + "\nARGUMENTS\n\t" + strings.Join(argsWithHelp, "\n\t"))
			return nil
		}
		return err
	}

	switch arg := cfg.Args.Num(0); arg {
	case argBootstrap:
		return bootstrap(cfg)
	case argGenerate:
		return generate(cfg)
	case argWipe:
		return wipe(filepath.Dir(foundConfigFile), cfg)
	default:
		return errors.New(arg + " is not a valid arg, possible arguments are:\n\t" + strings.Join(argsWithHelp, "\n\t"))
	}
}

func generate(cfg config) error {
	if cfg.Path != "" {
		configFile, err := os.Open(cfg.Path)
		if err != nil {
			return err
		}

		help, err := conf.Parse(namespace, &cfg, yaml.WithReader(configFile))
		if err == conf.ErrHelpWanted {
			fmt.Println(help + "")
			return nil
		}
		if err != nil {
			return err
		}
	}

	// If no service is given, set it to nil,
	// so the generation will run for all services
	service := &cfg.Service
	if cfg.Service == "" {
		service = nil
	}

	configFilePaths, err := getConfigFilePaths(cfg.Go.RootDir, cfg.Go.ServiceDir, service)
	if err != nil {
		return errors.Wrap(err, "cannot get config file paths")
	}

	for _, configFilePath := range configFilePaths {
		serviceDir := serviceDirectoryFromBoilerConfigPath(configFilePath)
		serviceName := serviceNameFromBoilerConfigPath(configFilePath)
		serviceModelDir := fmt.Sprintf("%s/model", serviceDir)
		definitionDir := fmt.Sprintf("%s/%s", cfg.Go.ServiceAPIDir, serviceName)
		conversionDir := fmt.Sprintf("%s/endpoint/conversion", serviceDir)
		endpointDir := fmt.Sprintf("%s/endpoint", serviceDir)
		ormDir := fmt.Sprintf("%s/repository/boiler/orm", serviceDir)
		repoDir := fmt.Sprintf("%s/repository/boiler", serviceDir)
		repositoryDir := fmt.Sprintf("%s/repository", serviceDir)

		pkgServiceModel := fmt.Sprintf("%s/%s/model", cfg.Go.ModuleName, serviceDir)
		pkgORM := fmt.Sprintf("%s/%s/repository/boiler/orm", cfg.Go.ModuleName, serviceDir)
		pkgConversion := fmt.Sprintf("%s/%s/endpoint/conversion", cfg.Go.ModuleName, serviceDir)
		pkgRepository := fmt.Sprintf("%s/%s/repository", cfg.Go.ModuleName, serviceDir)

		generationToConfig := map[string]boilerconfig.Wrapper{
			"orm":        boilerconfig.ORM(ormDir, pkgServiceModel, cfg.Go.Packages.Audit),
			"boiler":     boilerconfig.Boiler(repoDir, pkgORM, pkgServiceModel, pkgRepository, cfg.Go.Packages.Errors, cfg.Go.Packages.Audit, cfg.Go.Packages.Auth, cfg.Go.Packages.Database, cfg.Go.Packages.Logger, cfg.Go.Packages.Types, cfg.Stubs, cfg.Layer),
			"repository": boilerconfig.Repository(repositoryDir, pkgServiceModel, cfg.Go.Packages.Types, cfg.Stubs, cfg.Layer),
			"model":      boilerconfig.Model(serviceModelDir, cfg.Go.Packages.Types, cfg.Go.Packages.Errors, cfg.Go.Packages.Sort, cfg.Go.Packages.Valid),
			"definition": boilerconfig.Definition(definitionDir, serviceName, cfg.Stubs, cfg.Layer),
			"conversion": boilerconfig.Conversion(conversionDir, pkgServiceModel, cfg.Go.Packages.API, cfg.Go.Packages.Slice),
		}

		// Run default generation separately, since we dont want to set cross service join tables
		if err := runGeneration(cfg, configFilePath, serviceName, false, boilerconfig.Default(ormDir)); err != nil {
			return errors.Wrap(err, "default")
		}

		for generationName, generationConfig := range generationToConfig {
			if err := runGeneration(cfg, configFilePath, serviceName, true, generationConfig); err != nil {
				return errors.Wrap(err, generationName)
			}
		}

		if cfg.Stubs || cfg.Layer != "" {
			if cfg.Layer == "" || cfg.Layer == "service" {
				err = runGeneration(cfg, configFilePath, serviceName, true, boilerconfig.Service(serviceDir, serviceName, pkgRepository, pkgServiceModel, cfg.Go.Packages.Errors))
				if err != nil {
					return errors.Wrap(err, "service stubs")
				}
			}

			if cfg.Layer == "" || cfg.Layer == "endpoint" {
				err = runGeneration(cfg, configFilePath, serviceName, true, boilerconfig.Endpoint(endpointDir, serviceName, pkgServiceModel, pkgConversion, cfg.Go.Packages.API, cfg.Go.Packages.Types))
				if err != nil {
					return errors.Wrap(err, "endpoint stubs")
				}
			}
		}
	}

	err = removeDisclaimerFromStubs("./")
	if err != nil {
		return err
	}

	for i, o := range cfg.Oto {
		if o.Backend && cfg.OtoSkipBackend {
			continue
		}

		err := runGenerationWithOto(o.Template, o.Definition, o.OutputFile, o.PackageName, o.Ignore, o.Params, o.AfterScript, cfg.OtoSkipAfterScript, o.AddReturnObjectMethods)
		if err != nil {
			return errors.Wrapf(err, "oto generation failed at index %d for template %s", i, o.Template)
		}
	}

	return nil
}

func wipe(root string, cfg config) error {
	deleteGeneratedFiles := func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return errors.Wrap(err, "unexpected error getting generated file")
		}

		if info.IsDir() {
			return nil
		}

		dir, _ := filepath.Split(path)

		if !strings.Contains(info.Name(), ".gen.") && !strings.Contains(info.Name(), ".stub.") && !strings.HasSuffix(dir, "repository/boiler/orm") {
			return nil
		}

		// if specific service is specified we must make sure that the path includes the service name
		if cfg.Service != "" && !strings.Contains(path, "services/"+cfg.Service+"/") {
			return nil
		}

		switch cfg.Layer {
		case "":
			// if no layer is specifed, continue
		case "conversion":
			if !strings.Contains(path, "/endpoint/conversion/") {
				return nil
			}
		case "model":
			if !strings.Contains(path, "/model/") {
				return nil
			}
		case "repository":
			if !strings.Contains(path, "/repository/") {
				return nil
			}
		case "service":
			matches, err := filepath.Match("internal/services/*/*", path)
			if err != nil {
				return err
			}
			if !matches {
				return nil
			}
		case "api":
			if !strings.Contains(path, "api/services/") {
				return nil
			}
		default:
			return errors.New("invalid wipe layer options(conversion, model, repository, service, api)")
		}

		err = os.Remove(path)
		if err != nil {
			return errors.Wrapf(err, "cannot delete generated file (%s)", path)
		}

		return nil
	}

	err := filepath.Walk(root, deleteGeneratedFiles)
	if err != nil {
		return errors.Wrapf(err, "filepath %s", cfg.Go.RootDir)
	}

	return nil
}

func bootstrap(cfg config) error {
	serviceNameToMigrationsFolder := make(map[string]string)
	patternSuffix := "/repository/boiler/migrations"
	pattern := fmt.Sprintf("%s/*", fullGoServiceDir(cfg)) + patternSuffix
	folders, _ := filepath.Glob(pattern)
	for _, folder := range folders {
		// figure out service name by removing the suffix and getting the last slice element which will be the service name
		tmp := strings.Split(strings.TrimSuffix(folder, patternSuffix), "/")
		serviceName := tmp[len(tmp)-1]
		serviceNameToMigrationsFolder[serviceName] = folder
	}

	dsn := fmt.Sprintf("host=%s port=%d user=%s dbname=%s password=%s sslmode=%s",
		cfg.DB.Host,
		cfg.DB.Port,
		cfg.DB.User,
		cfg.DB.Name,
		cfg.DB.Password,
		cfg.DB.SSLMode,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return errors.Wrap(err, "failed to open db connection")
	}
	if err := gooseBootstrap(db, serviceNameToMigrationsFolder); err != nil {
		return errors.Wrap(err, "failed to bootstrap the database")
	}
	return nil
}

// gooseBootstrap accepts db sql connection and a map of service name to migration folder.
// it iterates through the map and runs migrations in the provided folder with table named service_name_goose_db_version.
func gooseBootstrap(db *sql.DB, serviceNameToMigrationFolder map[string]string) error {
	for serviceName, migrationFolder := range serviceNameToMigrationFolder {
		goose.SetBaseFS(os.DirFS(migrationFolder))
		// it replaces service name spaces with underscores and lowercase's the whole string
		goose.SetTableName(fmt.Sprintf("%s_goose_db_version", strings.ToLower(strings.Replace(serviceName, " ", "_", -1))))
		// since we already have migration folder we don't need to provide any dir
		if err := goose.Up(db, ""); err != nil {
			return err
		}
	}
	return nil
}

func runGenerationWithOto(templatePath, definitionPath, outputPath, packageName string, ignore []string, params map[string]interface{}, afterScript []string, skipAfterScript, addReturnObjectMethods bool) error {
	definitionFiles, err := filepath.Glob(definitionPath)
	if err != nil {
		return errors.Wrap(err, "cannot glob definition path")
	}

	// Add "./" as prefix since filepath.Glob removes it and the parser needs it
	if strings.HasPrefix(definitionPath, "./") {
		for i := range definitionFiles {
			definitionFiles[i] = "./" + definitionFiles[i]
		}
	}

	p := parser.New(definitionFiles...)
	p.ExcludeInterfaces = ignore

	def, err := p.Parse()
	if err != nil {
		return errors.Wrap(err, "cannot parse definitions")
	}

	for x := range def.Objects {
		if !def.ObjectIsOutput(def.Objects[x].Name) {
			continue
		}

		for y, field := range def.Objects[x].Fields {
			if field.Name == "Error" && field.Example == "something went wrong" {
				def.Objects[x].Fields = append(def.Objects[x].Fields[:y], def.Objects[x].Fields[y+1:]...)
			}
		}
	}

	for i, service := range def.Services {
		for _, method := range service.Methods {
			reload, ok := method.Metadata["reload"].(string)
			if !ok {
				continue
			}

			methodOutputObject, err := def.Object(method.OutputObject.CleanObjectName)
			if err != nil {
				return errors.Wrap(err, "cannot find output object for method ("+reload+")")
			}

			reloadServiceFound := false
			reloadMethodFound := false

			for _, reloadService := range def.Services {
				if !strings.HasPrefix(reload, reloadService.Name) {
					continue
				}

				reloadServiceFound = true

				for _, reloadMethod := range reloadService.Methods {
					if reload != fmt.Sprintf("%s.%s", reloadService.Name, reloadMethod.Name) {
						continue
					}

					reloadMethodFound = true

					reloadMethodInputObject, err := def.Object(reloadMethod.InputObject.CleanObjectName)
					if err != nil {
						return errors.Wrap(err, "cannot find input object for reload method ("+reload+")")
					}

					if len(reloadMethodInputObject.Fields) != len(methodOutputObject.Fields) {
						return errors.New("invalid output object for method, needs to be same fields as the reload methods input object (" + reload + ")")
					}

					inputFieldNameWithType := make(map[string]struct{})
					for _, field := range reloadMethodInputObject.Fields {
						inputFieldNameWithType[field.Name+field.Type.CleanObjectName] = struct{}{}
					}

					for _, field := range methodOutputObject.Fields {
						_, ok := inputFieldNameWithType[field.Name+field.Type.CleanObjectName]
						if !ok {
							return errors.New("invalid output object for method, needs to be same fields as the reload methods input object (" + reload + ")")
						}
					}

					if addReturnObjectMethods {
						method.Name += "WithReturnObject"
						method.NameLowerCamel += "WithReturnObject"
						method.NameLowerSnake += "with_return_object"
						method.OutputObject = reloadMethod.OutputObject

						def.Services[i].Methods = append(def.Services[i].Methods, method)
					}
				}
			}

			if !reloadServiceFound || !reloadMethodFound {
				return errors.New("cannot find method for reload: " + reload)
			}
		}
	}

	def.PackageName = packageName

	templateFile, err := os.Open(templatePath)
	if err != nil {
		return errors.Wrap(err, "cannot open template")
	}

	b, err := io.ReadAll(templateFile)
	if err != nil {
		return errors.Wrap(err, "cannot read template")
	}

	out, err := render.Render(string(b), def, params)
	if err != nil {
		return errors.Wrap(err, "cannot render output")
	}

	outputFile, err := os.Create(outputPath)
	if err != nil {
		return errors.Wrap(err, "cannot create output file")
	}
	defer func() { _ = outputFile.Close() }()

	_, err = io.WriteString(outputFile, out)
	if err != nil {
		return errors.Wrap(err, "cannot write to output file")
	}

	if skipAfterScript || len(afterScript) < 2 {
		return nil
	}

	err = exec.Command(afterScript[0], afterScript[1:]...).Run()
	if err != nil {
		return errors.Wrap(err, "cannot exec after script")
	}

	return nil
}

func runGeneration(cfg config, configFilePath, serviceName string, setCrossServiceJoinTable bool, configWrapper boilerconfig.Wrapper) error {
	boilerConfig, err := boilerconfig.GetConfig(boilerDriver, configFilePath, serviceName, cfg.Go.Packages.Types)
	if err != nil {
		return errors.Wrap(err, "cannot get boiler config")
	}

	configWrapper(boilerConfig)

	boilerState, err := boilerconfig.GetState(boilerConfig, cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode)
	if err != nil {
		return errors.Wrap(err, "cannot get boiler state")
	}

	if setCrossServiceJoinTable {
		for i, t := range boilerState.Tables {
			if t.IsJoinTable {
				continue
			}

			if len(t.Columns) != 2 && len(t.PKey.Columns) != 2 {
				continue
			}

			boilerState.Tables[i].IsJoinTable = true
		}
	}

	err = boilerState.Run()
	if err != nil {
		return errors.Wrap(err, "boilerstate run failed")
	}

	err = boilerState.Cleanup()
	if err != nil {
		return errors.Wrap(err, "boilerstate cleanup failed")
	}

	return nil
}

func getConfigFilePaths(rootDirectory, serviceDirectory string, service *string) ([]string, error) {
	var configFilePaths []string

	walkFunc := func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if service != nil && !strings.HasPrefix(path, filepath.Join(rootDirectory, serviceDirectory, *service)) {
			return nil
		}

		if info.IsDir() {
			return nil
		}

		if info.Name() != boilerConfigFile {
			return nil
		}

		configFilePaths = append(configFilePaths, path)
		return nil
	}

	err := filepath.Walk(filepath.Join(rootDirectory, serviceDirectory), walkFunc)
	if err != nil {
		return nil, err
	}

	return configFilePaths, nil
}

func fullGoServiceDir(c config) string {
	if c.Go.RootDir == "" || c.Go.RootDir == "./" {
		return c.Go.ServiceDir
	}
	return path.Clean(path.Join(c.Go.RootDir, c.Go.ServiceDir))
}

// findConfigFile searches for configFile in current directory and then repressively searches in parent directories.
// returns a first config path that it finds or empty string if no config was found
func findConfigFile() string {
	currentPath, err := os.Getwd()
	if err != nil {
		panic(err)
	}

	for currentPath != "/" {
		configPath := filepath.Join(currentPath, configFile)

		if _, err := os.Stat(configPath); err == nil {
			return configPath
		}

		currentPath = filepath.Dir(currentPath)
	}

	return ""
}

func serviceDirectoryFromBoilerConfigPath(boilerConfigPath string) string {
	return strings.TrimSuffix(boilerConfigPath, "/repository/boiler/"+boilerConfigFile)
}

func serviceNameFromBoilerConfigPath(boilerConfigPath string) string {
	_, serviceName := filepath.Split(serviceDirectoryFromBoilerConfigPath(boilerConfigPath))
	return serviceName
}

func removeDisclaimerFromStubs(rootDir string) error {
	return filepath.Walk(rootDir, func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if !strings.Contains(info.Name(), ".stub.") {
			return nil
		}

		file, err := os.Open(path)
		if err != nil {
			return err
		}

		defer file.Close()

		errSkipFile := errors.New("skip file")

		newContent := bytes.Buffer{}

		scanner := bufio.NewScanner(file)
		scannedLines := 0
		scanner.Split(func(data []byte, atEOF bool) (int, []byte, error) {
			advance, token, err := bufio.ScanLines(data, atEOF)
			if err != nil {
				return 0, nil, err
			}

			if scannedLines == 0 && !bytes.HasPrefix(token, []byte("// Code generated by SQLBoiler")) {
				return 0, nil, errSkipFile
			}

			scannedLines++

			if token == nil {
				return advance, nil, nil
			}

			switch scannedLines {
			case 1, 2, 3:
				return advance, token, nil
			}

			_, err = newContent.Write(append(token, '\n'))
			if err != nil {
				return 0, nil, err
			}

			return advance, token, nil
		})

		for scanner.Scan() {
			// Scan through the file and let the Split-function do the work
		}

		err = scanner.Err()
		if err == errSkipFile {
			return nil
		}
		if err != nil {
			return err
		}

		newFile, err := os.Create(path)
		if err != nil {
			return err
		}

		_, err = newFile.Write(newContent.Bytes())
		if err != nil {
			return err
		}

		return nil
	})
}
