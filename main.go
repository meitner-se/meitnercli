package main

import (
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

const boilerConfigFile = "sqlboiler.toml"
const namespace = "meitnercli"
const boilerDriver = "psql"
const configFile = "meitnercli.yml"

// Version is set during build.
var Version = "dev"

func main() {
	err := run(context.Background(), os.Args)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "received error when running generation: %v\n", err)
		os.Exit(1)
	}
}

type config struct {
	conf.Version
	Path        string `conf:"flag:config,env:CONFIG"`
	Service     string `conf:""`
	Stubs       bool   `conf:"default:false"`
	StubLayer   string `conf:""`
	Wipe        bool   `conf:"default:false"`
	WipeService string `conf:""`
	WipeLayer   string `conf:""`
	DB          dbConfig
	Go          struct {
		RootDir       string `conf:"default:./" yaml:"root_dir"`
		ServiceDir    string `conf:"default:./internal/services" yaml:"service_dir"`
		ServiceAPIDir string `conf:"default:./api/services" yaml:"service_api_dir"`
		ModuleName    string `conf:"default:meitner" yaml:"module_name"`
		Packages      struct {
			API    string `conf:"default:meitner/pkg/api"`
			Audit  string `conf:"default:meitner/pkg/audit"`
			Cache  string `conf:"default:meitner/pkg/cache"`
			Errors string `conf:"default:meitner/pkg/errors"`
			Types  string `conf:"default:meitner/pkg/types"`
		}
	}
	Oto []struct {
		Template    string         `conf:""`
		OutputFile  string         `conf:"" yaml:"output_file"`
		PackageName string         `conf:"" yaml:"package_name"`
		Definition  string         `conf:""`
		Ignore      []string       `conf:""`
		Params      map[string]any `conf:""`
		AfterScript []string       `conf:"" yaml:"after_script"`
	}
}

func (c config) fullGoServiceDir() string {
	if c.Go.RootDir == "" || c.Go.RootDir == "./" {
		return c.Go.ServiceDir
	}
	return path.Clean(path.Join(c.Go.RootDir, c.Go.ServiceDir))
}

type dbConfig struct {
	Name     string `conf:"default:meitner-dev"`
	User     string `conf:"default:meitner"`
	Password string `conf:"default:meitner"`
	Host     string `conf:"default:localhost"`
	Port     int    `conf:"default:5432"`
	SSLMode  string `conf:"default:disable"`
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

func run(_ context.Context, _ []string) error {
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
			fmt.Println(parseString)
			return nil
		}
		return err
	}

	var firstArgument string
	for _, arg := range os.Args[1:] {
		if !strings.HasPrefix(arg, "-") {
			firstArgument = arg
			break
		}
	}

	switch firstArgument {
	case "bootstrap":
		return bootstrap(cfg)
	case "generate":
		return generate(cfg)
	default:
		return printHelp(cfg)
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
			fmt.Println(help)
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

	if cfg.Wipe || cfg.WipeService != "" || cfg.WipeLayer != "" {
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
			if cfg.WipeService != "" {
				if !strings.Contains(path, "services/"+cfg.WipeService+"/") {
					return nil
				}
			}

			switch cfg.WipeLayer {
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
			case "":
			default:
				return errors.New("invalid wipe layer options(conversion, model, repository, service, api)")
			}

			err = os.Remove(path)
			if err != nil {
				return errors.Wrapf(err, "cannot delete generated file (%s)", path)
			}

			return nil
		}

		err := filepath.Walk(cfg.Go.RootDir, deleteGeneratedFiles)
		if err != nil {
			return errors.Wrapf(err, "filepath %s", cfg.Go.RootDir)
		}

		return nil
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
			"default":    boilerconfig.Default(ormDir),
			"orm":        boilerconfig.ORM(ormDir, pkgServiceModel, cfg.Go.Packages.Audit, cfg.Go.Packages.Cache),
			"boiler":     boilerconfig.Boiler(repoDir, pkgORM, pkgServiceModel, cfg.Go.Packages.Errors, cfg.Go.Packages.Audit, cfg.Go.Packages.Cache, cfg.Stubs, cfg.StubLayer),
			"repository": boilerconfig.Repository(repositoryDir, pkgServiceModel, cfg.Go.Packages.Types, cfg.Stubs, cfg.StubLayer),
			"model":      boilerconfig.Model(serviceModelDir, cfg.Go.Packages.Types, cfg.Go.Packages.Errors),
			"definition": boilerconfig.Definition(definitionDir, serviceName, cfg.Stubs, cfg.StubLayer),
			"conversion": boilerconfig.Conversion(conversionDir, pkgServiceModel, cfg.Go.Packages.API),
		}

		for generationName, generationConfig := range generationToConfig {
			if err := runGeneration(cfg, configFilePath, generationConfig); err != nil {
				return errors.Wrap(err, generationName)
			}
		}

		if cfg.Stubs || cfg.StubLayer != "" {
			if cfg.StubLayer == "" || cfg.StubLayer == "service" {
				err = runGeneration(cfg, configFilePath, boilerconfig.Service(serviceDir, serviceName, pkgRepository, pkgServiceModel))
				if err != nil {
					return errors.Wrap(err, "service stubs")
				}
			}

			if cfg.StubLayer == "" || cfg.StubLayer == "endpoint" {
				err = runGeneration(cfg, configFilePath, boilerconfig.Endpoint(endpointDir, serviceName, pkgServiceModel, pkgConversion, cfg.Go.Packages.API, cfg.Go.Packages.Types))
				if err != nil {
					return errors.Wrap(err, "endpoint stubs")
				}
			}
		}
	}

	for i, o := range cfg.Oto {
		err := runGenerationWithOto(o.Template, o.Definition, o.OutputFile, o.PackageName, o.Ignore, o.Params, o.AfterScript)
		if err != nil {
			return errors.Wrapf(err, "oto generation failed at index %d for template %s", i, o.Template)
		}
	}

	return nil
}

func bootstrap(cfg config) error {
	serviceNameToMigrationsFolder := make(map[string]string)
	patternSuffix := "/repository/boiler/migrations"
	pattern := fmt.Sprintf("%s/*", cfg.fullGoServiceDir()) + patternSuffix
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

func runGenerationWithOto(templatePath, definitionPath, outputPath, packageName string, ignore []string, params map[string]interface{}, afterScript []string) error {
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

	if len(afterScript) > 0 {
		err = exec.Command(afterScript[0], afterScript[1:]...).Run()
		if err != nil {
			return errors.Wrap(err, "cannot exec after script")
		}
	}

	return nil
}

func runGeneration(cfg config, configFilePath string, configWrapper boilerconfig.Wrapper) error {
	boilerConfig, err := boilerconfig.GetConfig(boilerDriver, configFilePath, cfg.Go.Packages.Types)
	if err != nil {
		return errors.Wrap(err, "cannot get boiler config")
	}

	configWrapper(boilerConfig)

	boilerState, err := boilerconfig.GetState(boilerConfig, cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode)
	if err != nil {
		return errors.Wrap(err, "cannot get boiler state")
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

func serviceDirectoryFromBoilerConfigPath(boilerConfigPath string) string {
	return strings.TrimSuffix(boilerConfigPath, "/repository/boiler/"+boilerConfigFile)
}

func serviceNameFromBoilerConfigPath(boilerConfigPath string) string {
	_, serviceName := filepath.Split(serviceDirectoryFromBoilerConfigPath(boilerConfigPath))
	return serviceName
}

func printHelp(cfg config) error {
	usageInfo, err := conf.UsageInfo(namespace, &cfg)
	if err != nil {
		return err
	}

	fmt.Println(usageInfo)
	return nil
}
