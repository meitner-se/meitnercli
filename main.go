package main

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/meitner-se/meitnercli/boilerconfig"

	"github.com/ardanlabs/conf/v3"
	"github.com/ardanlabs/conf/v3/yaml"
	"github.com/friendsofgo/errors"
	"github.com/meitner-se/oto/parser"
	"github.com/meitner-se/oto/render"
)

const boilerConfigFile = "sqlboiler.toml"

// Version is set during build.
var Version = "dev"

func main() {
	err := run(context.Background(), os.Args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "received error when running generation: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	cfg := struct {
		conf.Version
		Path    string `conf:"flag:config,env:CONFIG"`
		Service string `conf:""`
		Stubs   bool   `conf:"default:false"`
		Wipe    bool   `conf:"default:false"`
		DB      struct {
			Name     string `conf:"default:meitner-dev"`
			User     string `conf:"default:meitner"`
			Password string `conf:"default:meitner"`
			Host     string `conf:"default:localhost"`
			Port     int    `conf:"default:5432"`
			SSLMode  string `conf:"default:disable"`
		}
		Go struct {
			RootDir       string `conf:"default:./" yaml:"root_dir"`
			ServiceDir    string `conf:"default:./internal/services" yaml:"service_dir"`
			ServiceAPIDir string `conf:"default:./api/services" yaml:"service_api_dir"`
			ModuleName    string `conf:"default:meitner" yaml:"module_name"`
			Packages      struct {
				API    string `conf:"default:meitner/pkg/api"`
				Audit  string `conf:"default:meitner/pkg/audit"`
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
	}{
		Version: conf.Version{
			Build: Version,
			Desc:  "meitnercli is a tool which wraps sqlboiler to generate code from the database and oto to generate code from API-definitions",
		},
	}

	help, err := conf.Parse("meitnercli", &cfg)
	if err == conf.ErrHelpWanted {
		fmt.Fprint(os.Stdout, help)
		return nil
	}
	if err != nil {
		return err
	}

	if cfg.Path != "" {
		configFile, err := os.Open(cfg.Path)
		if err != nil {
			return err
		}

		help, err := conf.Parse("meitnercli", &cfg, yaml.WithReader(configFile))
		if err == conf.ErrHelpWanted {
			fmt.Fprint(os.Stdout, help)
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

	if cfg.Wipe {
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

	boilerDriver, err := boilerconfig.GetDriverName("psql")
	if err != nil {
		return err
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

		err := runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Default(ormDir))
		if err != nil {
			return errors.Wrap(err, "default")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.ORM(ormDir, pkgServiceModel, cfg.Go.Packages.Audit))
		if err != nil {
			return errors.Wrap(err, "orm")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Boiler(repoDir, pkgORM, pkgServiceModel, cfg.Go.Packages.Errors, cfg.Go.Packages.Audit, cfg.Stubs))
		if err != nil {
			return errors.Wrap(err, "boiler")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Repository(repositoryDir, pkgServiceModel, cfg.Go.Packages.Types, cfg.Stubs))
		if err != nil {
			return errors.Wrap(err, "repository")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Model(serviceModelDir, cfg.Go.Packages.Types, cfg.Go.Packages.Errors))
		if err != nil {
			return errors.Wrap(err, "model")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Definition(definitionDir, serviceName, cfg.Stubs))
		if err != nil {
			return errors.Wrap(err, "definition")
		}

		err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Conversion(conversionDir, pkgServiceModel, cfg.Go.Packages.API))
		if err != nil {
			return errors.Wrap(err, "conversion")
		}

		if cfg.Stubs {
			err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Service(serviceDir, serviceName, pkgRepository, pkgServiceModel))
			if err != nil {
				return errors.Wrap(err, "service stubs")
			}

			err = runGeneration(cfg.DB.Name, cfg.DB.User, cfg.DB.Password, cfg.DB.Host, cfg.DB.Port, cfg.DB.SSLMode, boilerDriver, configFilePath, cfg.Go.Packages.Types, boilerconfig.Endpoint(endpointDir, serviceName, pkgServiceModel, pkgConversion, cfg.Go.Packages.API, cfg.Go.Packages.Types))
			if err != nil {
				return errors.Wrap(err, "endpoint stubs")
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
	defer outputFile.Close()

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

func runGeneration(dbName, dbUser, dbPassword, dbHost string, dbPort int, dbSSLMode, boilerDriver, configFilePath, typesPackage string, configWrapper boilerconfig.Wrapper) error {
	cfg, err := boilerconfig.GetConfig(boilerDriver, configFilePath, typesPackage)
	if err != nil {
		return errors.Wrap(err, "cannot get boiler config")
	}

	configWrapper(cfg)

	boilerState, err := boilerconfig.GetState(cfg, dbName, dbUser, dbPassword, dbHost, dbPort, dbSSLMode)
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
