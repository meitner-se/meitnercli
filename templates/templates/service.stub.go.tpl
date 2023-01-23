// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

func (s *svc) Create{{ $alias.UpSingular }}(ctx context.Context, {{ $alias.DownSingular }} *model.{{ $alias.UpSingular }}) error {
	err := {{ $alias.DownSingular }}.Validate(false, s.validate{{ $alias.UpSingular }}Func(ctx))
	if err != nil {
		return err
	}

	err = s.repo.Create{{ $alias.UpSingular }}(ctx, {{ $alias.DownSingular }})
	if err != nil {
		return err
	}

	return nil
}

func (s *svc) Update{{ $alias.UpSingular }}(ctx context.Context, {{ $alias.DownSingular }} *model.{{ $alias.UpSingular }}) error {
	err := {{ $alias.DownSingular }}.Validate(true, s.validate{{ $alias.UpSingular }}Func(ctx))
	if err != nil {
		return err
	}

	return s.repo.Update{{ $alias.UpSingular }}(ctx, {{ $alias.DownSingular }})
}

func (s *svc) Delete{{ $alias.UpSingular }}(ctx context.Context, {{$pkArgs}}) error {
	{{ $alias.DownSingular }}, err := s.repo.Get{{ $alias.UpSingular }}(ctx, {{ $pkNames | join ", " }})
	if err != nil {
		return err
	}

	return s.repo.Delete{{ $alias.UpSingular }}(ctx, {{ $alias.DownSingular }})
}

func (s *svc) Get{{ $alias.UpSingular }}(ctx context.Context, {{$pkArgs}}) (*model.{{ $alias.UpSingular }}, error) {
	return s.repo.Get{{ $alias.UpSingular }}(ctx, {{ $pkNames | join ", " }})
}

func (s *svc) List{{ $alias.UpPlural }}(ctx context.Context, query model.{{ $alias.UpSingular }}Query) ([]*model.{{ $alias.UpSingular }}, *types.Int64, error) {
	return s.repo.List{{ $alias.UpPlural }}(ctx, query)
}

func (s *svc) validate{{ $alias.UpSingular }}Func(ctx context.Context) model.{{ $alias.UpSingular }}ValidateBusinessFunc {
	return func({{ $alias.DownSingular }} model.{{ $alias.UpSingular }}, isUpdate bool) error {
		return nil
	}
}

{{end -}}
