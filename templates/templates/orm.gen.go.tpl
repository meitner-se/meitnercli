{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkNamesFromStruct := prefixStringSlice "o." ($colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.titleCase | stringMap .StringFuncs.replaceReserved) -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}
{{- $stringTypes := "types.String, types.UUID, types.Time, types.Date" -}}

// InsertDefined inserts {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) InsertDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log, cacheClient cache.Client) error {
    whitelist := boil.Whitelist() // whitelist each column that has a defined value

    {{range $column := .Table.Columns}}
        {{$colAlias := $alias.Column $column.Name}}
        {{- if not $column.Nullable -}}
            if o.{{$colAlias}}.IsNil() {
                return errors.New("{{$column.Name}} cannot be null")
            }
        {{- end}}
        if o.{{$colAlias}}.IsDefined() {
            whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
        }
    {{- end}}

    err := o.Insert(ctx, exec, whitelist)
	if err != nil {
		return err
	}

    if o.R != nil {
    {{- range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if o.R.{{$relAlias.Local | plural }} != nil {
            err := o.Add{{$relAlias.Local | plural}}(ctx, exec, {{ not $rel.ToJoinTable }}, o.R.{{$relAlias.Local | plural }}...)
            if err != nil {
                return err
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    }

    err = auditLog.Add(ctx, audit.OperationCreate, TableNames.{{titleCase .Table.Name}}, o.ID.String())
    if err != nil {
        return err
    }

    {{ range $fKey := .Table.FKeys }}
        err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpPlural}}", "{{ titleCase $fKey.Column }}", o.{{ titleCase $fKey.Column }}.String()))
        if err != nil {
            return errors.Wrap(err, "cannot delete from cache")
        }
    {{ end }}

    return nil
}

// UpdateDefined updates {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) UpdateDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log, cacheClient cache.Client, newValues *{{$alias.UpSingular}}) error {
    auditLogValues := []audit.LogValue{} // Collect all values that have been changed
    whitelist := boil.Whitelist() // whitelist each column that has a defined value and should be updated

    {{range $column := .Table.Columns}}
    {{$colAlias := $alias.Column $column.Name}}
        if newValues.{{$colAlias}}.IsDefined() {{ if ne $column.Type "types.JSON" }}&& newValues.{{$colAlias}}.String() != o.{{$colAlias}}.String() {{end}} {
            {{- if not $column.Nullable -}}
                if newValues.{{$colAlias}}.IsNil() {
                    return errors.New("{{$column.Name}} cannot be null")
                }
            {{- end}}
            auditLogValues = append(auditLogValues, audit.NewLogValue({{$alias.UpSingular}}Columns.{{$colAlias}}, "{{ stripPrefix $column.Type "types." }}", newValues.{{$colAlias}}, o.{{$colAlias}}, false))
            whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
            o.{{$colAlias}} = newValues.{{$colAlias}}
        }
    {{- end}}

    // Check if any join tables should be updated and load the existing values before updating if we have an operating audit log
    if newValues.R != nil {
        {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            if newValues.R.{{$relAlias.Local | plural }} != nil {
                {{$relAlias.Local | singular | camelCase }}Slice, err := o.{{$relAlias.Local | plural }}().All(ctx, exec)
                if err != nil {
                    return err
                }

                if o.R == nil {
                    o.R = o.R.NewStruct()
                }

                o.R.{{$relAlias.Local}} = {{$relAlias.Local | singular | camelCase }}Slice

                new{{$relAlias.Local | singular}}IDs := newValues.Get{{$relAlias.Local | singular}}IDs(true)
                old{{$relAlias.Local | singular}}IDs := o.Get{{$relAlias.Local | singular}}IDs(true)

                if !slices.Match(new{{$relAlias.Local | singular}}IDs, old{{$relAlias.Local | singular}}IDs) {
                    auditLogValues = append(auditLogValues, audit.NewLogValue(model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, "UUID", new{{$relAlias.Local | singular}}IDs, old{{$relAlias.Local | singular}}IDs, true))

                    {{ if $rel.ToJoinTable }}
                        err := o.Set{{$relAlias.Local | plural}}(ctx, exec, false, newValues.R.{{$relAlias.Local | plural }}...)
                        if err != nil {
                            return err
                        }
                    {{ else }}
                        _, err := o.R.{{$relAlias.Local}}.DeleteAll(ctx, exec)
                        if err != nil {
                            return err
                        }

                        err = o.Add{{$relAlias.Local | plural}}(ctx, exec, true, newValues.R.{{$relAlias.Local | plural }}...)
                        if err != nil {
                            return err
                        }
                    {{ end -}}
                }
            }
        {{end -}}{{- /* range relationships */ -}}
    }

    if len(whitelist.Cols) > 0 {
        {{if not .NoRowsAffected}}_,{{end -}} err := o.Update(ctx, exec, whitelist)
        if err != nil {
            return err
        }
	}

    err := auditLog.Add(ctx, audit.OperationUpdate, TableNames.{{titleCase .Table.Name}}, o.ID.String(), auditLogValues...)
    if err != nil {
        return err
    }

    err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpSingular}}", {{- $pkNamesFromStruct | join ".String(), " -}}.String()))
    if err != nil {
        return err
    }

    {{- range $column := .Table.Columns }}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
            err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpSingular}}", "{{$colAlias}}", o.{{ $colAlias }}.String()))
            if err != nil {
                return err
            }
        {{- end -}}
    {{- end -}}

    {{- range $fKey := .Table.FKeys }}
        err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpPlural}}", "{{ titleCase $fKey.Column }}", o.{{ titleCase $fKey.Column }}.String()))
        if err != nil {
            return err
        }
    {{ end }}

    return nil
}

// DeleteDefined deletes {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) DeleteDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log, cacheClient cache.Client) error {
     auditLogValues := []audit.LogValue{
    {{- range $column := .Table.Columns -}}
        {{ $colAlias := $alias.Column $column.Name }}
        audit.NewLogValue({{$alias.UpSingular}}Columns.{{$colAlias}}, "{{ stripPrefix $column.Type "types." }}", nil, o.{{$colAlias}}, false),
    {{- end }}
    {{ range $rel := getLoadRelations $.Tables .Table -}}{{- if $rel.ToJoinTable -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        audit.NewLogValue(model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, "UUID", nil, o.Get{{$relAlias.Local | singular}}IDs(true), true),
    {{end -}}{{end -}}
    }

        if o.R != nil {
            {{- range $rel := getLoadRelations $.Tables .Table -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
                if len(o.R.{{$relAlias.Local | plural }}) > 0 {
                    {{- if $rel.ToJoinTable }}
                        err := o.Remove{{$relAlias.Local | plural}}(ctx, exec, o.R.{{$relAlias.Local | plural }}...)
                        if err != nil {
                            return err
                        }
                    {{ else }}
                        _, err := o.R.{{$relAlias.Local}}.DeleteAll(ctx, exec)
                        if err != nil {
                            return err
                        }
                    {{ end -}}
                }
            {{end -}}{{- /* range relationships */ -}}
        }

    {{if not .NoRowsAffected}}_,{{end -}}err := o.Delete(ctx, exec)
	if err != nil {
		return err
	}

    err = auditLog.Add(ctx, audit.OperationDelete, TableNames.{{titleCase .Table.Name}}, o.ID.String(), auditLogValues...)
    if err != nil {
        return err
    }

    err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpSingular}}", {{- $pkNamesFromStruct | join ".String(), " -}}.String()))
    if err != nil {
        return err
    }

    {{- range $column := .Table.Columns }}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
            err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpSingular}}", "{{$colAlias}}", o.{{ $colAlias }}.String()))
            if err != nil {
                return err
            }
        {{- end -}}
    {{- end -}}

    {{- range $fKey := .Table.FKeys }}
        err = cacheClient.Delete(ctx, cache.DefaultKey("{{$alias.UpPlural}}", "{{ titleCase $fKey.Column }}", o.{{ titleCase $fKey.Column }}.String()))
        if err != nil {
            return err
        }
    {{ end }}

    return nil
}

{{ range $rel := getLoadRelations $.Tables .Table -}}
{{- $ftable := $.Aliases.Table .ForeignTable -}}
{{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
{{ $loadCol := getLoadRelationColumn $.Tables $rel }}
{{ $loadType := getLoadRelationType $.Aliases $.Tables $rel "model." }}
func (o *{{$alias.UpSingular}}) Get{{ getLoadRelationName $.Aliases $rel }}(load bool) []{{ $loadType }} {
    if o.R == nil || o.R.{{ $relAlias.Local | plural }} == nil {
        if load {
            return []{{ $loadType }}{}
        }
		return nil
	}

	{{ $relAlias.Local | plural | camelCase }} := make([]{{ $loadType }}, len(o.R.{{ $relAlias.Local | plural }}))
	for i := range o.R.{{ $relAlias.Local | plural }} {
		{{ $relAlias.Local | plural | camelCase }}[i] = o.R.{{ $relAlias.Local | plural }}[i].{{ $loadCol.Name | titleCase }}
	}

	return {{ $relAlias.Local | plural | camelCase }}
}

func (o *{{$alias.UpSingular}}) Set{{ getLoadRelationName $.Aliases $rel }}({{ $relAlias.Local | plural | camelCase }} []{{ $loadType }}) {
    if {{ $relAlias.Local | plural | camelCase }} == nil {
        return
    }

    if o.R == nil {
		o.R = &{{$alias.DownSingular}}R{}
	}

	o.R.{{ $relAlias.Local | plural }} =  make({{$ftable.UpSingular}}Slice, len({{ $relAlias.Local | plural | camelCase }}))
	for i := range {{ $relAlias.Local | plural | camelCase }} {
        o.R.{{ $relAlias.Local | plural }}[i] = &{{$ftable.UpSingular}}{
            {{- if not $rel.ToJoinTable }}
                {{ $rel.ForeignColumn | titleCase }}: o.ID,
            {{ end -}}
            {{ $loadCol.Name | titleCase }}: {{ $relAlias.Local | plural | camelCase }}[i],
        }
	}
}
{{end}}

func Get{{$alias.UpSingular}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, cacheClient cache.Client, {{ $pkArgs }}) (*model.{{$alias.UpSingular}}, error) {
    var fromCache model.{{$alias.UpSingular}}
    err := cacheClient.Scan(ctx, cache.DefaultKey("{{$alias.UpSingular}}", {{- $pkNames | join ".String(), " -}}.String()), &fromCache)
    if err != nil && err != cache.ErrNotFound {
        return nil, errors.Wrap(err, "cannot scan from cache")
    }

    if nil == err {
        return &fromCache, nil
    }

    // Create queryMods from SelectedFields as nil, which will load all relations by default,
    // which is expected when using the Get-method
    queryMods := getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(nil)

    // Add the primary keys to the query
    {{- range $pkName := $pkNames }}
        queryMods = append(queryMods, {{$alias.UpSingular}}Where.{{ $pkName | titleCase }}.EQ({{ $pkName }}))
    {{ end }}

    fromDB, err := {{$alias.UpPlural}}(queryMods...).One({{if not $.NoContext}}ctx,{{end}} exec)
    if err != nil {
        return nil, err
    }

    {{$alias.DownSingular}} := {{$alias.UpSingular}}ToModel(fromDB{{- range getLoadRelations $.Tables .Table -}}, true {{ end }})

    err = cacheClient.Set(ctx, cache.DefaultKey("{{$alias.UpSingular}}", {{- $pkNames | join ".String(), " -}}.String()), {{$alias.DownSingular}})
    if err != nil {
        return nil, errors.Wrap(err, "cannot set to cache")
    }
    
    return {{$alias.DownSingular}}, nil
}

{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
    {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
	    func Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, cacheClient cache.Client, {{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error) {
            var fromCache model.{{$alias.UpSingular}}
            err := cacheClient.Scan(ctx, cache.DefaultKey("{{$alias.UpSingular}}", "{{$colAlias}}", {{ camelCase $colAlias }}.String()), &fromCache)
            if err != nil && err != cache.ErrNotFound {
                return nil, errors.Wrap(err, "cannot scan from cache")
            }

            if nil == err {
                return &fromCache, nil
            }

            // Create queryMods from SelectedFields as nil, which will load all relations by default,
            // which is expected when using the GetByUnique-method
            queryMods := getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(nil)
            queryMods = append(queryMods, {{$alias.UpSingular}}Where.{{ $colAlias }}.EQ({{ camelCase $colAlias }}))

            fromDB, err := {{$alias.UpPlural}}(queryMods...).One({{if not $.NoContext}}ctx,{{end}} exec)
            if err != nil {
                return nil, err
            }

            {{$alias.DownSingular}} := {{$alias.UpSingular}}ToModel(fromDB{{- range getLoadRelations $.Tables $.Table -}}, true {{ end }})

            err = cacheClient.Set(ctx, cache.DefaultKey("{{$alias.UpSingular}}", "{{$colAlias}}", {{ camelCase $colAlias }}.String()), {{$alias.DownSingular}})
            if err != nil {
                return nil, errors.Wrap(err, "cannot set to cache")
            }

            return {{$alias.DownSingular}}, nil
        }
    {{ end }}
{{end -}}

func List{{$alias.UpPlural}}({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
	queryModsForCount, queryModsWithPagination := getQueryModsFrom{{$alias.UpSingular}}Query(query)

	{{$alias.DownPlural}}, err := {{$alias.UpPlural}}(queryModsWithPagination...).All({{if not .NoContext}}ctx,{{end}} exec)
	if err != nil {
		return nil, nil, err
	}

    var (
        {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            load{{$relAlias.Local | singular}} bool = true
        {{ end }}
    )

    if query.SelectedFields != nil {
        {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            load{{$relAlias.Local | singular}} = query.SelectedFields.{{$relAlias.Local | singular }}IDs.Bool()
        {{ end -}}
    }

    // If offset and limit is nil, pagination is not used.
    // So if this happens we do not have to call the DB to get the total count without pagination.
    if query.Offset.IsNil() && query.Limit.IsNil() {
        return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}{{- range $rel := getLoadRelations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular }} {{ end }}), types.NewInt64(int64(len({{$alias.DownPlural}}))).Ptr(), nil
    }

    // Get the total count without pagination
    primaryKeys := []string{}
    {{- range $pkName := $pkNames }}
        primaryKeys = append(primaryKeys, {{$alias.UpSingular}}QueryColumns.{{$pkName | titleCase}})
    {{- end}}

    queryModsForCount = append(queryModsForCount, qm.Distinct(strings.Join(primaryKeys, ", ")))
	{{$alias.DownPlural}}Count, err := {{$alias.UpPlural}}(queryModsForCount...).Count({{if not .NoContext}}ctx,{{end}}  exec)
	if err != nil {
		return nil, nil, err
	}

	return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}{{- range $rel := getLoadRelations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular }} {{ end }}), types.NewInt64({{$alias.DownPlural}}Count).Ptr(), nil
}

{{ range $fKey := .Table.FKeys -}}
func List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, cacheClient cache.Client, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error) {
    var fromCache model.{{$alias.UpPlural}}
    err := cacheClient.Scan(ctx, cache.DefaultKey("{{$alias.UpPlural}}", "{{ titleCase $fKey.Column }}", {{ camelCase $fKey.Column }}.String()), &fromCache)
    if err != nil && err != cache.ErrNotFound {
        return nil, errors.Wrap(err, "cannot scan from cache")
    }

    if nil == err {
        return fromCache, nil
    }

    // Create queryMods from SelectedFields as nil, which will load all relations by default,
    // which is expected when using the ListByFK-method
    queryMods := getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(nil)
    queryMods = append(queryMods, {{$alias.UpSingular}}Where.{{ titleCase $fKey.Column }}.EQ({{ camelCase $fKey.Column }}))

    // Add the default order by columns defined in the schema to keep consistency
    orderByStrings := []string{}
    {{- range getTableOrderByColumns $.Table }}
        orderByStrings = append(orderByStrings, `{{ . }}`)
    {{- end}}

    {{- range $pkName := $pkNames }}
        orderByStrings = append(orderByStrings, {{$alias.UpSingular}}QueryColumns.{{$pkName | titleCase}} + " asc")
    {{- end}}

    queryMods = append(queryMods, qm.OrderBy(strings.Join(orderByStrings, ",")))

    fromDB, err := {{$alias.UpPlural}}(queryMods...).All({{if not $.NoContext}}ctx,{{end}} exec)
    if err != nil {
        return nil, err
    }

    {{$alias.DownPlural}} := model.{{$alias.UpPlural}}({{$alias.UpSingular}}ToModels(fromDB{{- range getLoadRelations $.Tables $.Table -}}, true {{ end }}))

    err = cacheClient.Set(ctx, cache.DefaultKey("{{$alias.UpPlural}}", "{{ titleCase $fKey.Column }}", {{ camelCase $fKey.Column }}.String()), &{{$alias.DownPlural}})
    if err != nil {
        return nil, errors.Wrap(err, "cannot set to cache")
    }

    return {{$alias.DownPlural}}, nil
}
{{ end }}

func {{$alias.UpSingular}}FromModel(model *model.{{$alias.UpSingular}}) *{{$alias.UpSingular}} {
    {{$alias.DownSingular}} := &{{$alias.UpSingular}}{
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{$colAlias}}: model.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }},
        {{ end -}}
    }
    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{$alias.DownSingular}}.Set{{ getLoadRelationName $.Aliases $rel }}(model.{{ getLoadRelationName $.Aliases $rel }})
    {{end -}}{{- /* range relationships */ -}}
    return  {{$alias.DownSingular}}
}

func {{$alias.UpSingular}}ToModel(toModel *{{$alias.UpSingular}}{{ range $rel := getLoadRelations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}} bool{{ end }}) *model.{{$alias.UpSingular}} {
    return &model.{{$alias.UpSingular}}{
        {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}}: {{ if (isEnumDBType .DBType) }}{{- $enumName := parseEnumName .DBType -}} model.{{ titleCase $enumName }}FromString(toModel.{{$colAlias}}) {{ else }} toModel.{{$colAlias}} {{ end }},
        {{- end}}
        {{ range $rel := getLoadRelations $.Tables .Table -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{ getLoadRelationName $.Aliases $rel }}: toModel.Get{{ getLoadRelationName $.Aliases $rel }}(load{{$relAlias.Local | singular}}),
        {{end -}}{{- /* range relationships */ -}}
    }
}

func {{$alias.UpSingular}}ToModels(toModels []*{{$alias.UpSingular}}{{ range $rel := getLoadRelations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}} bool{{ end }}) []*model.{{$alias.UpSingular}} {
    models := make([]*model.{{$alias.UpSingular}}, len(toModels))
    for i := range toModels {
        models[i] = {{$alias.UpSingular}}ToModel(toModels[i]{{ range $rel := getLoadRelations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}}{{ end }})
    }
    return models
}

func getQueryModsFrom{{$alias.UpSingular}}Query(q model.{{$alias.UpSingular}}Query) ([]qm.QueryMod, []qm.QueryMod) {
    queryWrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
        if q.OrCondition.Bool() {
            return qm.Or2(queryMod)
        }
        return queryMod
    }

    queryForCount := getQueryModsFrom{{$alias.UpSingular}}QueryParams(q.Params, queryWrapperFunc)

    for i := range q.Nested {
        queryForCount = append(queryForCount, queryWrapperFunc(getQueryModsFrom{{$alias.UpSingular}}QueryNested(&q.Nested[i])))
    }

    // Wrap the query if we have a wrapper
    if q.Wrapper != nil {
        queryWrapped := []qm.QueryMod{getQueryModsFrom{{$alias.UpSingular}}QueryNested(q.Wrapper)}
        if len(queryForCount) == 0 {
            queryWrapped = append(queryWrapped, queryForCount...)
        } else {
            queryWrapped = append(queryWrapped, qm.Expr(queryForCount...))
        }
        queryForCount = queryWrapped
    }

    queryForCount = append(queryForCount, getQueryModsFrom{{$alias.UpSingular}}QueryForJoin(q)...)

    queryWithPagination := queryForCount
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(q.SelectedFields)...)
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QueryOrderBy(q.OrderBy)...)

    // If offset and limit is nil, do not append them to the query
    if q.Offset.IsNil() && q.Limit.IsNil() {
        return queryForCount, queryWithPagination
    }

    queryWithPagination = append(queryWithPagination, []qm.QueryMod{
		qm.Offset(q.Offset.Int()),
		qm.Limit(q.Limit.Int()),
	}...)

    return queryForCount, queryWithPagination
}

func getQueryModsFrom{{$alias.UpSingular}}QueryNested(q *model.{{$alias.UpSingular}}QueryNested) qm.QueryMod {
	queryWrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
		if q.OrCondition.Bool() {
			return qm.Or2(queryMod)
		}
		return queryMod
	}

	query := []qm.QueryMod{}
	query = append(query, getQueryModsFrom{{$alias.UpSingular}}QueryParams(q.Params, queryWrapperFunc)...)

    for i := range q.Nested {
        query = append(query, queryWrapperFunc(getQueryModsFrom{{$alias.UpSingular}}QueryNested(&q.Nested[i])))
    }

    // We had an issue when the client sends an empty nested query: {"nested": {}}
    // which resulted in an SQL-statement like this: WHERE (id = $1 AND ()),
    // to solve this we will return a where statement which just says "true",
    // the SQL-statement will instead result in: WHERE (id = $1 AND (true))
	if len(query) == 0 {
		return qm.Where("true")
	}

	return qm.Expr(query...)
}

func getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(q *model.{{$alias.UpSingular}}QuerySelectedFields) []qm.QueryMod {
    query := []qm.QueryMod{}
    selectedFields := []string{}

    {{ if ne (len $pkNames) 0 }}
    // Always select primary keys as distinct (required when joining on many2many relationships)
    primaryKeys := []string{}
    {{- range $pkName := $pkNames }}
        primaryKeys = append(primaryKeys, {{$alias.UpSingular}}QueryColumns.{{$pkName | titleCase}})
    {{- end}}
        selectedFields = append(selectedFields, "DISTINCT ("+ strings.Join(primaryKeys, ", ") + ")")
    {{end}}

    // If there are no selected fields, all fields will be selected by default,
    // therefore we to load the relations as well, to get the expected result.
    if q == nil {
        selectedFields = append(selectedFields, {{$alias.DownSingular}}AllQueryColumns...)
        query = append(query, qm.Select(strings.Join(selectedFields, ", ")))
        {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            query = append(query, qm.Load({{$alias.UpSingular}}Rels.{{ $relAlias.Local | plural }}))
        {{ end -}}

        return query
    }

    {{ range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        if q.{{$colAlias}}.Bool() {
            selectedFields = append(selectedFields, {{$alias.UpSingular}}QueryColumns.{{$colAlias}})
        }
    {{- end}}

    query = append(query, qm.Select(strings.Join(selectedFields, ", ")))

    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if q.{{$relAlias.Local | singular }}IDs.Bool() {
            query = append(query, qm.Load({{$alias.UpSingular}}Rels.{{ $relAlias.Local | plural }}))
        }
    {{ end }}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryParams(q model.{{$alias.UpSingular}}QueryParams, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}

    if q.Equals != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}EQ(q.Equals, queryWrapperFunc)...)
    }
    if q.NotEquals != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NEQ(q.NotEquals, queryWrapperFunc)...)
    }

    if q.Empty != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}Empty(q.Empty, queryWrapperFunc)...)
    }
    if q.NotEmpty != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotEmpty(q.NotEmpty, queryWrapperFunc)...)
    }

    if q.In != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}In(q.In, queryWrapperFunc)...)
    }
    if q.NotIn != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotIn(q.NotIn, queryWrapperFunc)...)
    }

    if q.GreaterThan != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterThan(q.GreaterThan, queryWrapperFunc)...)
    }
    if q.SmallerThan != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerThan(q.SmallerThan, queryWrapperFunc)...)
    }

    if q.GreaterOrEqual != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterOrEqual(q.GreaterOrEqual, queryWrapperFunc)...)
    }
    if q.SmallerOrEqual != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerOrEqual(q.SmallerOrEqual, queryWrapperFunc)...)
    }

    if q.Like != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}Like(q.Like, queryWrapperFunc)...)
    }
    if q.NotLike != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotLike(q.NotLike, queryWrapperFunc)...)
    }

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}EQ(q *model.{{$alias.UpSingular}}QueryParamsFields, queryWrapperFunc func(q qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{ if not (hasSuffix "JSON" $column.Type) -}}
            if !q.{{$colAlias}}.IsNil() {
                {{- if or (eq $column.Type "types.String") (isEnumDBType .DBType) -}}
                    if q.CaseInsensitive.Bool() {
                        query = append(query, queryWrapperFunc(whereHelpertypes_String{field: fmt.Sprintf("LOWER(%s)", {{$alias.UpSingular}}Where.{{$colAlias}}.field)}.EQ(types.NewString(strings.ToLower(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }}.String())))))
                    } else {
                        query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.EQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
                    }
                {{- else }}
                    query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.EQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
                {{- end }}
            }
        {{- end -}}
    {{- end}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := getLoadRelationColumn $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if !q.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ getLoadRelationTableColumn $.Tables $rel }}"}.EQ(q.{{ getLoadRelationName $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}EQ(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}EQ(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NEQ(q *model.{{$alias.UpSingular}}QueryParamsFields, queryWrapperFunc func(q qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{ if not (hasSuffix "JSON" $column.Type) -}}
            if !q.{{$colAlias}}.IsNil() {
                {{- if or (eq $column.Type "types.String") (isEnumDBType .DBType) -}}
                    if q.CaseInsensitive.Bool() {
                        query = append(query, queryWrapperFunc(whereHelpertypes_String{field: fmt.Sprintf("LOWER(%s)", {{$alias.UpSingular}}Where.{{$colAlias}}.field)}.NEQ(types.NewString(strings.ToLower(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }}.String())))))
                    } else {
                        query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.NEQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
                    }
                {{- else }}
                    query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.NEQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
                {{- end }}
            }
        {{- end -}}
    {{- end}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := getLoadRelationColumn $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if !q.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ getLoadRelationTableColumn $.Tables $rel }}"}.NEQ(q.{{ getLoadRelationName $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NEQ(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NEQ(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}Empty(q *model.{{$alias.UpSingular}}QueryParamsNullableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}

        {{- if containsAny $.Table.PKey.Columns $column.Name }}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNull())) // Primary key is nullable on left joins
            }
        {{- end}}

        {{if $column.Nullable -}}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNull()))
            }
        {{- end}}

    {{- end}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}Empty(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}Empty(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotEmpty(q *model.{{$alias.UpSingular}}QueryParamsNullableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}

        {{- if containsAny $.Table.PKey.Columns $column.Name }}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNotNull())) // Primary key is nullable on left joins
            }
        {{- end}}

        {{if $column.Nullable -}}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNotNull()))
            }
        {{- end}}

    {{- end}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotEmpty(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotEmpty(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}In(q *model.{{$alias.UpSingular}}QueryParamsInFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if not (isEnumDBType .DBType) }}
        {{- if or (contains $column.Type $stringTypes) (hasPrefix "types.Int" $column.Type) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IN(q.{{$colAlias}})))
            }
        {{- end}}
        {{- end}}
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := getLoadRelationColumn $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if q.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ getLoadRelationTableColumn $.Tables $rel }}"}.IN(q.{{ getLoadRelationName $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}In(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}In(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotIn(q *model.{{$alias.UpSingular}}QueryParamsInFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if and (not (isEnumDBType .DBType)) (or (eq "types.String" $column.Type) (eq "types.UUID" $column.Type)) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.NIN(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := getLoadRelationColumn $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if q.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ getLoadRelationTableColumn $.Tables $rel }}"}.NIN(q.{{ getLoadRelationName $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotIn(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotIn(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}GreaterThan(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.GT(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}GreaterThan(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}GreaterThan(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}SmallerThan(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.LT(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}SmallerThan(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}SmallerThan(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}GreaterOrEqual(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.GTE(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}GreaterOrEqual(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}GreaterOrEqual(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}SmallerOrEqual(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.LTE(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}SmallerOrEqual(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}SmallerOrEqual(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}Like(q *model.{{$alias.UpSingular}}QueryParamsLikeFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if and (hasSuffix "String" $column.Type) (not (isEnumDBType .DBType)) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc(qm.Where({{$alias.UpSingular}}Where.{{$colAlias}}.field + " ILIKE ?", "%"+q.{{$colAlias}}.String()+"%")))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}Like(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}Like(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotLike(q *model.{{$alias.UpSingular}}QueryParamsLikeFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if and (hasSuffix "String" $column.Type) (not (isEnumDBType .DBType)) -}}
            if !q.{{$colAlias}}.IsNil() {
                query = append(query, queryWrapperFunc(qm.Where({{$alias.UpSingular}}Where.{{$colAlias}}.field + " NOT ILIKE ?", "%"+q.{{$colAlias}}.String()+"%")))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotLike(q.{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if q.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
           query = append(query, getQueryModsFrom{{ $rel.ForeignTable | titleCase }}NotLike(q.LeftJoin{{ $rel.ForeignTable | titleCase }}, queryWrapperFunc)...)
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryForJoin(q model.{{$alias.UpSingular}}Query) []qm.QueryMod {
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        join{{$relAlias.Local | singular }} := false
    {{end }}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        join{{$relAlias.Local | singular }} := false
    {{end }}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        joinLeft{{$relAlias.Local | singular }} := false
    {{end }}

    checkParams := func(p model.{{$alias.UpSingular}}QueryParams) {
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if p.Equals != nil {
            if !p.Equals.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotEquals != nil {
            if !p.NotEquals.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.In != nil {
            if p.In.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if p.Equals != nil {
            if p.Equals.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.Equals.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotEquals != nil {
            if p.NotEquals.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.NotEquals.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.Empty != nil {
            if p.Empty.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.Empty.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotEmpty != nil {
            if p.NotEmpty.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.NotEmpty.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.In != nil {
            if p.In.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.In.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.NotIn.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.GreaterThan != nil {
            if p.GreaterThan.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.GreaterThan.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.SmallerThan != nil {
            if p.SmallerThan.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.SmallerThan.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.SmallerOrEqual != nil {
            if p.SmallerOrEqual.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.SmallerOrEqual.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.GreaterOrEqual != nil {
            if p.GreaterOrEqual.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.GreaterOrEqual.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.Like != nil {
            if p.Like.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.Like.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotLike != nil {
            if p.NotLike.{{ $rel.ForeignTable | titleCase }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
            if p.NotLike.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                joinLeft{{$relAlias.Local | singular }} = true
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    }

    checkParams(q.Params)
	for _, nested := range q.Nested {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, nested)
	}

	if q.Wrapper != nil {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, *q.Wrapper)
	}

    query := []qm.QueryMod{}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if join{{$relAlias.Local | singular }} {
            query = append(query, qm.LeftOuterJoin("{{ getLoadRelationStatement $.Aliases $.Tables $rel }}"))
        }
    {{end }}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if join{{$relAlias.Local | singular }} {
            query = append(query, qm.InnerJoin("\"{{ $rel.ForeignTable }}\" ON \"{{ $rel.Table }}\".\"{{ $rel.Column }}\" = \"{{ $rel.ForeignTable }}\".\"{{ $rel.ForeignColumn }}\""))
        } else if joinLeft{{$relAlias.Local | singular }} {
            query = append(query, qm.LeftOuterJoin("\"{{ $rel.ForeignTable }}\" ON \"{{ $rel.Table }}\".\"{{ $rel.Column }}\" = \"{{ $rel.ForeignTable }}\".\"{{ $rel.ForeignColumn }}\""))
        }
    {{end }}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryOrderBy(q *model.{{$alias.UpSingular}}QueryOrderBy) []qm.QueryMod {
    getOrder := func(desc bool) string {
        if desc {
            return "desc"
        }
        return "asc"
    }

    type orderByField struct {
        field string
        order  string
        index  int
    }

    var orderByFields []orderByField
    if q != nil {
        {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
                if q.{{$colAlias}} != nil {
                    orderByFields = append(orderByFields, orderByField{
                        field: {{$alias.UpSingular}}QueryColumns.{{$colAlias}},
                        order: getOrder(q.{{$colAlias}}.Desc),
                        index: q.{{$colAlias}}.Index,
                    })
                }
        {{- end}}
    }

    sort.Slice(orderByFields, func(i, j int) bool {
        return orderByFields[i].index < orderByFields[j].index
    })

    orderByStrings := []string{}
    for _, o := range orderByFields {
        orderByStrings = append(orderByStrings, o.field + " " + o.order)
    }

    // Add the default order by columns defined in the schema to keep consistency
    {{- range getTableOrderByColumns .Table }}
        orderByStrings = append(orderByStrings, `{{ . }}`)
    {{- end}}

    {{- range $pkName := $pkNames }}
        orderByStrings = append(orderByStrings, {{$alias.UpSingular}}QueryColumns.{{$pkName | titleCase}} + " asc")
    {{- end}}

	return []qm.QueryMod{
        qm.OrderBy(strings.Join(orderByStrings, ",")),
    }
}

func check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc func(model.{{$alias.UpSingular}}QueryParams), nested model.{{$alias.UpSingular}}QueryNested) {
	checkParamsFunc(nested.Params)

	for i := range nested.Nested {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc, nested.Nested[i])
	}
}

var {{$alias.UpSingular}}QueryColumns = struct {
	{{range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{$colAlias}} string
	{{end -}}
}{
	{{range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{$colAlias}}: "\"{{$.Table.Name}}\".\"{{$column.Name}}\"",
	{{end -}}
}

var {{$alias.DownSingular}}AllQueryColumns = []string{
	{{range $column := .Table.Columns -}}
	"\"{{$.Table.Name}}\".\"{{$column.Name}}\"",
	{{end -}}
}

{{- range .Table.Columns -}}
{{- if (oncePut $.DBTypes .Type)}}
{{- if not (or (isPrimitive .Type) (isNullPrimitive .Type) (isEnumDBType .DBType)) -}}
{{- if or (contains .Type $stringTypes) (hasPrefix "types.Int" .Type) }}

{{$name := printf "whereHelper%s" (goVarname .Type)}}

func (w {{$name}}) IN(slice []{{.Type}}) qm.QueryMod {
	values := make([]interface{}, 0, len(slice))
	for _, value := range slice {
		values = append(values, value)
	}
	return qm.WhereIn(w.field + " IN ?", values...)
}
func (w {{$name}}) NIN(slice []{{.Type}}) qm.QueryMod {
	values := make([]interface{}, 0, len(slice))
	for _, value := range slice {
	  values = append(values, value)
	}
	return qm.WhereNotIn(w.field + " NOT IN ?", values...)
}

{{end}}
{{end}}
{{end}}
{{end}}

{{end -}}

// Init blank variables since these packages might not be needed
var (
    _ = fmt.Sprintf
	_ = strconv.IntSize
    _ = time.Now // For setting timestamps to entities
    _ = uuid.Nil // For generation UUIDs to entities
    _ = slices.Match[string] // For comparing slices when updating m2m relations
)
