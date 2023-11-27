{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

func (s *svc) Create{{ $alias.UpSingular }}(ctx context.Context, {{ $alias.DownSingular }} *model.{{ $alias.UpSingular }}) error {
	err := {{ $alias.DownSingular }}.NormalizeAndValidate(ctx, false, s.validate{{ $alias.UpSingular }}Func(ctx))
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
	err := {{ $alias.DownSingular }}.NormalizeAndValidate(ctx, true, s.validate{{ $alias.UpSingular }}Func(ctx))
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

// validate{{ $alias.UpSingular }}Func is used to validate the business logic for the {{ $alias.UpSingular }}-entity
func (s *svc) validate{{ $alias.UpSingular }}Func(ctx context.Context) model.{{ $alias.UpSingular }}ValidateBusinessFunc {
    {{ $alias.DownSingular }}Validator := model.{{ $alias.UpSingular }}Validator{
    	// GetFunc is only used on update to get the {{ $alias.UpSingular }} and merge all the undefined values for convenience on validation
        GetFunc: s.Get{{ $alias.UpSingular }},
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- if not (or (eq $column.Name "id") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
            {{$colAlias}}: nil,
        {{end -}}
        {{end -}}
        {{- range $rel := getLoadRelations $.Tables .Table -}}
            {{ getLoadRelationName $.Aliases $rel }}: nil,
        {{end -}}
    }

	return func({{ $alias.DownSingular }} model.{{ $alias.UpSingular }}, isUpdate bool) error {
		return {{ $alias.DownSingular }}Validator.Validate(ctx, {{ $alias.DownSingular }}, isUpdate)
	}
}
