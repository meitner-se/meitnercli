package templates

import "embed"

var (
	//go:embed templates/boiler.gen.go.tpl
	Boiler embed.FS

	//go:embed templates/boiler.gen.go.tpl
	//go:embed templates/singleton/boiler.stub.go.tpl
	BoilerWithStub embed.FS

	//go:embed templates/conversion.gen.go.tpl
	Conversion embed.FS

	//go:embed templates/definition.def.gen.go.tpl
	Definition embed.FS

	//go:embed templates/definition.def.gen.go.tpl
	//go:embed templates/singleton/api_*.go.tpl
	DefinitionWithStub embed.FS

	//go:embed templates/singleton/endpoint_*.go.tpl
	EndpointStub embed.FS

	//go:embed templates/model.gen.go.tpl
	Model embed.FS

	//go:embed templates/orm.gen.go.tpl
	ORM embed.FS

	//go:embed templates/repository.gen.go.tpl
	Repository embed.FS

	//go:embed templates/repository.gen.go.tpl
	//go:embed templates/singleton/repository.stub.go.tpl
	RepositoryWithStub embed.FS

	//go:embed templates/service.stub.go.tpl
	//go:embed templates/singleton/service.stub.go.tpl
	ServiceStub embed.FS

	//go:embed templates/integration_test.query_test.stub.go.tpl
	//go:embed templates/integration_test.command_test.stub.go.tpl
	//go:embed templates/singleton/base_setup_test.stub.go.tpl
	IntegrationTestStub embed.FS
)
