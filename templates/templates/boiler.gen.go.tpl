{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $colNames := .Table.Columns | columnNames -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

func (r *repo) Create{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {	
	return r.WithinTransaction(ctx, func(ctx context.Context) error {
		exec := database.GetBoilExec(ctx, r.db)

		// Make sure to set the values of the auto-columns to the service model pointer, since they might be used by the caller.
		// The auto-columns for insert are: "ID", "CreatedAt", "UpdatedAt", "CreatedBy", "UpdatedBy"
		{{- range $ind, $col := .Table.Columns -}}
			{{- $colAlias := $alias.Column $col.Name -}}
			{{- if or (eq $col.Name (or $.AutoColumns.Created "created_at")) }}
				input.{{$colAlias}} = types.NewTimestamp(time.Now().UTC())
			{{- end -}}
			{{- if eq $col.Name "created_by" }}
				input.{{$colAlias}} = auth.GetCurrentUserID(ctx)
			{{- end -}}
		{{ end }}
		
		{{- $numberOfPKeys := len .Table.PKey.Columns }}
		{{ if and (containsAny $colNames "id") (eq $numberOfPKeys 1) }}
			// Generate the ID if it hasn't been set already
			if !input.ID.IsDefined() {
				id, err := uuid.NewRandom()
				if err != nil {
					return errors.Wrap(err, "cannot generate uuid")
				}

				input.ID = types.NewUUID(id)
			}
		{{ end }}

		if err := orm.{{$alias.UpSingular}}FromModel(input).InsertDefined(ctx, exec, r.audit); err != nil {
			return errors.Wrap(err, errors.MessageCannotCreateEntity("{{$alias.DownSingular}}"))
		}

		return nil
	})
}

func (r *repo) Update{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {
	return r.WithinTransaction(ctx, func(ctx context.Context) error {
		exec := database.GetBoilExec(ctx, r.db)

		{{$alias.DownSingular}}, err := orm.Find{{$alias.UpSingular}}(ctx, exec, {{ prefixStringSlice "input." ($colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.titleCase) | join ", " }})
		if err == sql.ErrNoRows {
			return errors.NewNotFoundWrapped(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
		}
		if err != nil {
			return errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
		}

		// Make sure to set the values of the auto-columns to the service model pointer, since they might be used by the caller.
		// The auto-columns for update are: "UpdatedAt", "UpdatedBy"

		{{- range $ind, $col := .Table.Columns -}}
			{{- $colAlias := $alias.Column $col.Name -}}
			{{- if or (eq $col.Name (or $.AutoColumns.Updated "updated_at")) }}
				input.{{$colAlias}} = types.NewTimestamp(time.Now().UTC())
			{{- end -}}
			{{- if eq $col.Name "updated_by" }}
				input.{{$colAlias}} = auth.GetCurrentUserID(ctx)
			{{- end -}}
		{{ end }}

		err = {{$alias.DownSingular}}.UpdateDefined(ctx, exec, r.audit, orm.{{$alias.UpSingular}}FromModel(input))
		if err != nil {
			return errors.Wrap(err, errors.MessageCannotUpdateEntity("{{$alias.DownSingular}}"))
		}

		return nil
	})
}

func (r *repo) Delete{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {
	return r.WithinTransaction(ctx, func(ctx context.Context) error {
		exec := database.GetBoilExec(ctx, r.db)

		err := orm.{{$alias.UpSingular}}FromModel(input).DeleteDefined(ctx, exec, r.audit)
		if err != nil {
			return errors.Wrap(err, errors.MessageCannotDeleteEntity("{{$alias.DownSingular}}"))
		}

    	return nil
	})
}

func (r *repo) Get{{$alias.UpSingular}}(ctx context.Context, {{ $pkArgs }}) (*model.{{$alias.UpSingular}}, error) {
	{{$alias.DownSingular}}, err := orm.Get{{$alias.UpSingular}}(ctx, r.db, {{ $pkNames | join ", " }})
	if err == sql.ErrNoRows {
		return nil, errors.NewNotFoundWrapped(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}
	if err != nil {
		return nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

	return {{$alias.DownSingular}}, nil
}

func (r *repo) Get{{$alias.UpSingular}}WithQueryParams(ctx context.Context, queryParams model.{{$alias.UpSingular}}QueryParams, orCondition bool) (*model.{{$alias.UpSingular}}, error) {
	query := model.New{{$alias.UpSingular}}Query()
	query.Params = queryParams
	query.OrCondition = types.NewBool(orCondition)
	query.Limit = types.NewInt(1)
	query.Offset = types.NewInt(0)

	{{$alias.DownPlural}}, _, err := r.List{{$alias.UpPlural}}(ctx, query)
	if err != nil {
		return nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

	if len({{$alias.DownPlural}}) == 0 {
		return nil, errors.NewNotFoundWrapped(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}
	
	return {{$alias.DownPlural}}[0], nil
}

{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
    {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
	    func (r *repo) Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}{{else}}ctx context.Context,{{end}}{{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error) {
                {{$alias.DownSingular}}, err := orm.Get{{$alias.UpSingular}}By{{ titleCase $colAlias}}({{if $.NoContext}}{{else}}ctx,{{end}} r.db, {{ camelCase $colAlias }})
                if err == sql.ErrNoRows {
					return nil, errors.NewNotFoundWrapped(err, errors.MessageCannotFindEntityByKey("{{$alias.DownSingular}}", "{{ camelCase $colAlias }}"))
				}
				if err != nil {
                    return nil, err
                }
                
                return {{$alias.DownSingular}}, nil
        }
    {{ end }}
{{end -}}

func (r *repo) List{{$alias.UpPlural}}(ctx context.Context, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
    {{$alias.DownPlural}}, totalCount, err := orm.List{{$alias.UpPlural}}(ctx, r.db, query)
    if err != nil {
		return nil, nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

    return {{$alias.DownPlural}}, totalCount, nil
}

{{ range $fKey := .Table.FKeys -}}
func (r *repo) List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}{{else}}ctx context.Context{{end}}, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error) {
    {{$alias.DownPlural}}, err := orm.List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}(ctx, r.db, {{ camelCase $fKey.Column }})
	if err != nil {
		return nil, errors.Wrap(err, errors.MessageCannotFindEntityFromEntity("{{$alias.DownSingular}}", "{{ $fKey.ForeignTable }}"))
	}

    return {{$alias.DownPlural}}, nil
}
{{ end }}

{{end -}}

// Init blank variables since these packages might not be needed
var (
	_ = strconv.IntSize
    _ = time.Second 	// Force time package dependency for automated UpdatedAt/CreatedAt.
    _ = uuid.Nil 		// Force uuid package dependency for generation UUIDs to entities
	_ auth.Service
)
