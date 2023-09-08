{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $colNames := .Table.Columns | columnNames -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

func (r *repo) Create{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Create{{$alias.UpSingular}}")
    defer span.End()

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
        if input.ID.IsNil() {
            id, err := uuid.NewRandom()
            if err != nil {
                return errors.Wrap(err, "cannot generate uuid")
            }

            input.ID = types.NewUUID(id)
        }
    {{ end }}

    if err := orm.{{$alias.UpSingular}}FromModel(input).InsertDefined(ctx, exec, r.audit, r.cache); err != nil {
        return errors.Wrap(err, errors.MessageCannotCreateEntity("{{$alias.DownSingular}}"))
    }

    return nil
}

func (r *repo) Update{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Update{{$alias.UpSingular}}")
    defer span.End()

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

    err = {{$alias.DownSingular}}.UpdateDefined(ctx, exec, r.audit, r.cache, orm.{{$alias.UpSingular}}FromModel(input))
    if err != nil {
        return errors.Wrap(err, errors.MessageCannotUpdateEntity("{{$alias.DownSingular}}"))
    }

    return nil
}

func (r *repo) Delete{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Delete{{$alias.UpSingular}}")
    defer span.End()

    exec := database.GetBoilExec(ctx, r.db)

    err := orm.{{$alias.UpSingular}}FromModel(input).DeleteDefined(ctx, exec, r.audit, r.cache)
    if err != nil {
        return errors.Wrap(err, errors.MessageCannotDeleteEntity("{{$alias.DownSingular}}"))
    }

    return nil
}

func (r *repo) Get{{$alias.UpSingular}}(ctx context.Context, id types.UUID) (*model.{{$alias.UpSingular}}, error) {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Get{{$alias.UpSingular}}")
    defer span.End()

	query := model.New{{$alias.UpSingular}}Query()
	query.Params = model.New{{$alias.UpSingular}}QueryParams()
	query.Params.Equals = model.New{{$alias.UpSingular}}QueryParamsFields()
	query.Params.Equals.ID = id

    return r.get{{$alias.UpSingular}}(ctx, query)
}

func (r *repo) Get{{$alias.UpSingular}}WithQueryParams(ctx context.Context, queryParams model.{{$alias.UpSingular}}QueryParams) (*model.{{$alias.UpSingular}}, error) {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Get{{$alias.UpSingular}}WithQueryParams")
    defer span.End()

	query := model.New{{$alias.UpSingular}}Query()
	query.Params = queryParams

    return r.get{{$alias.UpSingular}}(ctx, query)
}

{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
    {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
	    func (r *repo) Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}{{else}}ctx context.Context,{{end}}{{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error) {
	            ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.Get{{$alias.UpSingular}}By{{$colAlias}}")
                defer span.End()

                query := model.New{{$alias.UpSingular}}Query()
                query.Params.Equals = model.New{{$alias.UpSingular}}QueryParamsFields()
                query.Params.Equals.{{$colAlias}} = {{ camelCase $colAlias }}

                return r.get{{$alias.UpSingular}}(ctx, query)
        }
    {{ end }}
{{end -}}

func (r *repo) List{{$alias.UpPlural}}(ctx context.Context, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.List{{$alias.UpPlural}}")
    defer span.End()

    {{ if tableHasQueryWrapper .Table }}
        // TODO : Activate this wrapper
        //if err := wrap{{$alias.UpSingular}}Query(ctx, &query); err != nil {
        //    return nil, nil, errors.Wrap(err, "failed to wrap query")
        //}
    {{ end }}

    exec := database.GetBoilExec(ctx, r.db)

    {{$alias.DownPlural}}, totalCount, err := orm.List{{$alias.UpPlural}}(ctx, exec, query)
    if err != nil {
		return nil, nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

    return {{$alias.DownPlural}}, totalCount, nil
}

{{ range $fKey := .Table.FKeys -}}
func (r *repo) List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}{{else}}ctx context.Context{{end}}, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error) {
    ctx, span := r.tracer.Start(ctx, "{{ getServiceName }}.List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}")
    defer span.End()

    query := model.New{{$alias.UpSingular}}Query()
    query.Params.Equals = model.New{{$alias.UpSingular}}QueryParamsFields()
    query.Params.Equals.{{ titleCase $fKey.Column }} = {{ camelCase $fKey.Column }}

    {{$alias.DownPlural}}, _, err := r.List{{$alias.UpPlural}}(ctx, query)
    if err != nil {
		return nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

    return {{$alias.DownPlural}}, nil
}
{{ end }}

func (r *repo) get{{$alias.UpSingular}}(ctx context.Context, query model.{{$alias.UpSingular}}Query) (*model.{{$alias.UpSingular}}, error) {
	{{$alias.DownPlural}}, _, err := r.List{{$alias.UpPlural}}(ctx, query)
	if err != nil {
		return nil, errors.Wrap(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

	if len({{$alias.DownPlural}}) > 1 {
		return nil, errors.Wrap(err, "got bigger result than expected")
	}

	if len({{$alias.DownPlural}}) == 0 {
		return nil, errors.NewNotFoundWrapped(err, errors.MessageCannotFindEntity("{{$alias.DownSingular}}"))
	}

	return {{$alias.DownPlural}}[0], nil
}

{{ if tableHasQueryWrapper .Table }}
func wrap{{$alias.UpSingular}}Query(ctx context.Context, q *model.{{$alias.UpSingular}}Query) error {
	claims, err := auth.GetClaims(ctx)
	if err != nil && err != auth.ErrNotFoundClaims {
		return errors.Wrap(err, "cannot get claims")
	}

	if claims == nil {
		return nil // Nothing to wrap
	}

	if claims.Organization == nil {
		return nil // Nothing to wrap
	}

	q.Wrapper = q.NewWrapper()
    q.Wrapper.Params.Equals = model.New{{$alias.UpSingular}}QueryParamsFields()

    {{- if tableHasColumnOrganizationID .Table }}
	    q.Wrapper.Params.Equals.OrganizationID = claims.Organization.TopOrganizationID
    {{- end }}

    {{ if or (tableHasColumnSchoolOrganizationID .Table) (tableHasColumnUnitOrganizationID .Table) }}
        switch {
        {{- if tableHasColumnSchoolOrganizationID .Table }}
            case claims.Organization.OrganizationCategory.IsSchool():
            	q.Wrapper.Params.Equals.SchoolOrganizationID = claims.Organization.ActiveOrganizationID
        {{- end -}}

        {{- if tableHasColumnUnitOrganizationID .Table }}
            case claims.Organization.OrganizationCategory.IsUnit():
            	q.Wrapper.Params.Equals.UnitOrganizationID = claims.Organization.ActiveOrganizationID
        {{- end -}}
        }
    {{ end }}

	return nil
}
{{ end }}

{{end -}}

// Init blank variables since these packages might not be needed
var (
	_ = strconv.IntSize
    _ = time.Second 	// Force time package dependency for automated UpdatedAt/CreatedAt.
    _ = uuid.Nil 		// Force uuid package dependency for generation UUIDs to entities
	_ auth.Claims
)
