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

func List{{$alias.UpPlural}}({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
    if err := query.Validate(); err != nil {
        return nil, nil, err
    }

    queryString, queryParams := {{$alias.UpSingular}}QueryStatementWithPagination(ctx, &query)

    rows, err := exec.QueryContext(ctx, queryString, queryParams...)
    if err != nil {
    	return nil, nil, errors.Wrap(err, "cannot query with context for {{$alias.DownPlural}}")
    }

    defer rows.Close()

    {{$alias.DownPlural}} := make([]*model.{{$alias.UpSingular}}, 0)

    for rows.Next() {
    	var {{$alias.DownSingular}} model.{{$alias.UpSingular}}

    	if err := rows.Scan(get{{$alias.UpSingular}}ValuesForScan(&{{$alias.DownSingular}}, query.Fields)...); err != nil {
    		return nil, nil, errors.Wrap(err, "cannot scan row for {{$alias.DownSingular}}")
    	}

    	{{$alias.DownPlural}} = append({{$alias.DownPlural}}, &{{$alias.DownSingular}})
    }

    if err := rows.Err(); err != nil {
    	return nil, nil, errors.Wrap(err, "got error from rows")
    }

    {{ if hasLoadRelations $.Tables .Table }}
        if err := load{{$alias.UpSingular}}Relationships(ctx, exec, query.Fields, {{$alias.DownPlural}}...); err != nil {
            return nil, nil, errors.Wrap(err, "got error when loading relationships")
        }
    {{ end }}

    // If offset and limit is nil, pagination is not used.
    // So if this happens we do not have to call the DB to get the total count without pagination.
    if query.Offset.IsNil() && query.Limit.IsNil() {
        return {{$alias.DownPlural}}, types.NewInt64(int64(len({{$alias.DownPlural}}))).Ptr(), nil
    }

    queryString, queryParams = {{$alias.UpSingular}}QueryStatementForCount(ctx, &query)

	row := exec.QueryRowContext(ctx, queryString, queryParams...)
	if err := row.Err(); err != nil {
		return nil, nil, errors.Wrap(err, "cannot query row with context for {{$alias.DownPlural}} count")
	}

	var count types.Int64
	if err := row.Scan(&count); err != nil {
		return nil, nil, errors.Wrap(err, "cannot scan row to get count")
	}

	return {{$alias.DownPlural}}, count.Ptr(), nil
}

{{ if hasLoadRelations $.Tables .Table }}
func load{{$alias.UpSingular}}Relationships(ctx context.Context, exec boil.ContextExecutor, fields *model.{{$alias.UpSingular}}QueryFieldsWithOrderBy, {{$alias.DownPlural}} ...*model.{{$alias.UpSingular}}) error {
    if len({{$alias.DownPlural}}) == 0 {
        return nil // Nothing to load since we don't have any {{$alias.DownPlural}}
    }

    var (
        {{$alias.DownSingular}}IDs = make([]string, len({{$alias.DownPlural}}))
        {{$alias.DownSingular}}Map = make(map[string]*model.{{$alias.UpSingular}}, len({{$alias.DownPlural}}))
    )

    for i, {{$alias.DownSingular}} := range {{$alias.DownPlural}} {
    	{{$alias.DownSingular}}IDs[i] = {{$alias.DownSingular}}.ID.String()
    	{{$alias.DownSingular}}Map[{{$alias.DownSingular}}.ID.String()] = {{$alias.DownSingular}}
    }

    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if fields.{{$relAlias.Local | singular }}IDs {
            err := load{{$alias.UpSingular}}{{$relAlias.Local | singular }}IDs(ctx, exec, {{$alias.DownSingular}}IDs, {{$alias.DownSingular}}Map)
            if err != nil {
                return errors.Wrap(err, "failed to load {{$relAlias.Local | singular }}IDs")
            }
        }
    {{ end }}

    return nil
}
{{ end }}

{{ range $rel := getLoadRelations $.Tables .Table }}
{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
func load{{$alias.UpSingular}}{{$relAlias.Local | singular }}IDs(ctx context.Context, exec boil.ContextExecutor, {{$alias.DownSingular}}IDs []string, {{$alias.DownSingular}}Map map[string]*model.{{$alias.UpSingular}}) error {
    // Initialize the slice for the related IDs,
    // since a nil slice means that the relation shouldn't have been loaded,
    // but an empty slice means that the relation have been loaded.
    for _, {{$alias.DownSingular}} := range {{$alias.DownSingular}}Map {
        {{$alias.DownSingular}}.{{$relAlias.Local | singular }}IDs = make([]types.UUID, 0)
    }

	rows, err := exec.QueryContext(ctx, "SELECT \"{{ $rel.JoinLocalColumn }}\", \"{{ $rel.JoinForeignColumn }}\" FROM {{ getLoadRelationForeignTable $.Aliases $.Tables $rel }} WHERE \"{{ $rel.JoinLocalColumn }}\" = ANY($1::uuid[])", pq.StringArray({{$alias.DownSingular}}IDs))
	if err != nil {
		return err
	}

	defer rows.Close()

	for rows.Next() {
		var (
			{{ $rel.JoinLocalColumn | camelCase }}  string
			{{ $rel.JoinForeignColumn | camelCase }} types.UUID
		)

		if err := rows.Scan(&{{ $rel.JoinLocalColumn | camelCase }}, &{{ $rel.JoinForeignColumn | camelCase }}); err != nil {
			return err
		}

		{{$alias.DownSingular}}, ok := {{$alias.DownSingular}}Map[{{ $rel.JoinLocalColumn | camelCase }}]
		if !ok {
		    return errors.New("did not find {{$alias.DownSingular}}-object for load: "+{{ $rel.JoinLocalColumn | camelCase }})
		}

        {{$alias.DownSingular}}.{{$relAlias.Local | singular }}IDs = append({{$alias.DownSingular}}.{{$relAlias.Local | singular }}IDs, {{ $rel.JoinForeignColumn | camelCase }})
	}

	return nil
}
{{end}}

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

func check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc func(model.{{$alias.UpSingular}}QueryParams), nested model.{{$alias.UpSingular}}QueryNested) {
	checkParamsFunc(nested.Params)

	for i := range nested.Nested {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc, nested.Nested[i])
	}
}

func {{$alias.UpSingular}}QueryStatementWithPagination(ctx context.Context, q *model.{{$alias.UpSingular}}Query) (string, []any) {
    // TODO : Add context deadline, this method should be fast and not be slower than a second (generous)

	queryBuilder := querybuilder.New("\"{{ .Table.Name }}\"")

	build{{$alias.UpSingular}}QuerySelectWithColumns(q, queryBuilder)
	build{{$alias.UpSingular}}QueryJoins(q, queryBuilder)
	build{{$alias.UpSingular}}QueryWhere(q, queryBuilder)
	build{{$alias.UpSingular}}QueryOffset(q, queryBuilder)
	build{{$alias.UpSingular}}QueryLimit(q, queryBuilder)

	span := trace.SpanFromContext(ctx)

	return fmt.Sprintf("-- TraceID:%s\n%s",
	    span.SpanContext().TraceID().String(),
	    queryBuilder.String(),
    ), queryBuilder.Params()
}

func {{$alias.UpSingular}}QueryStatementForCount(ctx context.Context, q *model.{{$alias.UpSingular}}Query) (string, []any) {
    // TODO : Add context deadline, this method should be fast and not be slower than a second (generous)

	queryBuilder := querybuilder.New("\"{{ .Table.Name }}\"")

	build{{$alias.UpSingular}}QuerySelectForCount(q, queryBuilder)
	build{{$alias.UpSingular}}QueryJoins(q, queryBuilder)
	build{{$alias.UpSingular}}QueryWhere(q, queryBuilder)

	span := trace.SpanFromContext(ctx)

	return fmt.Sprintf("-- TraceID:%s\n%s",
	    span.SpanContext().TraceID().String(),
	    queryBuilder.String(),
    ), queryBuilder.Params()
}

func build{{$alias.UpSingular}}QuerySelectForCount(q *model.{{$alias.UpSingular}}Query, selector querybuilder.Selector) {
    // If the query has a left join, wrap the primary key with a distinct on
    if {{$alias.DownSingular}}QueryHasLeftJoin(q) {
        selector.Select("COUNT(DISTINCT (" + {{$alias.UpSingular}}QueryColumns.ID + "))")
    } else {
        selector.Select("COUNT(" + {{$alias.UpSingular}}QueryColumns.ID + ")")
    }
}

func build{{$alias.UpSingular}}QuerySelectWithColumns(q *model.{{$alias.UpSingular}}Query, selector querybuilder.Selector) {
    if q.Fields == nil {
        q.Fields = all{{$alias.UpSingular}}QueryFields
    }

    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        if q.Fields.{{$colAlias}}.Selected {
            {{- if isPrimaryKey $.Table $column }}
                // If the query has a left join, wrap the primary key with a distinct on
                if {{$alias.DownSingular}}QueryHasLeftJoin(q) {
                    selector.DistinctOn({{$alias.UpSingular}}QueryColumns.{{$colAlias}})
                }
            {{- end }}
            if q.Fields.{{$colAlias}}.OrderBy != nil {
                selector.SelectWithOrderBy({{$alias.UpSingular}}QueryColumns.{{$colAlias}}, q.Fields.{{$colAlias}}.OrderBy.Index, q.Fields.{{$colAlias}}.OrderBy.Desc)
            } else {
                selector.Select({{$alias.UpSingular}}QueryColumns.{{$colAlias}})
            }
        }
    {{- end}}
}

func build{{$alias.UpSingular}}QueryJoins(q *model.{{$alias.UpSingular}}Query, joiner querybuilder.Joiner) {
    {{- range $rel := getLoadRelations $.Tables .Table }}
    {{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if {{$alias.DownSingular}}QueryHasJoinOn{{$relAlias.Local | singular }}(q) {
            joiner.LeftOuterJoin("{{ getLoadRelationForeignTable $.Aliases $.Tables $rel }}", "{{ getLoadRelationForeignKey $.Aliases $.Tables $rel }}", "{{ getLoadRelationReferenceKey $.Aliases $.Tables $rel }}")
        }
    {{end -}}
    {{ range $rel := getJoinRelations $.Tables .Table }}
    {{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if {{$alias.DownSingular}}QueryHasJoinOn{{$relAlias.Local | singular }}(q) {
            joiner.InnerJoin("\"{{ $rel.ForeignTable }}\"", "\"{{ $rel.ForeignTable }}\".\"{{ $rel.ForeignColumn }}\"", "\"{{ $rel.Table }}\".\"{{ $rel.Column }}\"")
        } else if {{$alias.DownSingular}}QueryHasLeftJoinOn{{$relAlias.Local | singular }}(q) {
            joiner.LeftOuterJoin("\"{{ $rel.ForeignTable }}\"", "\"{{ $rel.ForeignTable }}\".\"{{ $rel.ForeignColumn }}\"", "\"{{ $rel.Table }}\".\"{{ $rel.Column }}\"")
        }
    {{end -}}
}

func build{{$alias.UpSingular}}QueryWhere(q *model.{{$alias.UpSingular}}Query, where querybuilder.Where) {
    if !{{$alias.DownSingular}}QueryHasWhere(q) {
        return
    }

    whereClause := where.NewWhereClause(q.OrCondition.Bool())

    // If the query has a wrapper, override the where clause with it
	if q.HasWrapper() {
		whereClause = where.NewWhereClause(q.Wrapper.OrCondition.Bool())

		build{{$alias.UpSingular}}QueryWhereRecursive(q.Wrapper, whereClause)

        // If the query only has a wrapper, we can return early
		if !q.HasNested() && !q.Params.IsSet() {
			return
		}

        // Create a new nested clause of the user defined query
		whereClause = whereClause.NewNested(q.OrCondition.Bool())
	}

    if q.Params.IsSet() {
        build{{$alias.UpSingular}}QueryWhereParams(&q.Params, whereClause)
    }

    for i := range q.Nested {
        build{{$alias.UpSingular}}QueryWhereRecursive(&q.Nested[i], whereClause)
    }
}

func build{{$alias.UpSingular}}QueryWhereRecursive(q *model.{{$alias.UpSingular}}QueryNested, where querybuilder.WhereClause) {
    whereClause := where.NewNested(q.OrCondition.Bool())

    if q.Params.IsSet() {
        build{{$alias.UpSingular}}QueryWhereParams(&q.Params, whereClause)
    }

    for i := range q.Nested {
        build{{$alias.UpSingular}}QueryWhereRecursive(&q.Nested[i], whereClause)
    }
}

func build{{$alias.UpSingular}}QueryWhereParams(params *model.{{$alias.UpSingular}}QueryParams, where querybuilder.WhereClause) {
    if params.Equals != nil {
        build{{$alias.UpSingular}}QueryWhereParamsFields(params.Equals, where.Equals)
    }
    if params.NotEquals != nil {
        build{{$alias.UpSingular}}QueryWhereParamsFields(params.NotEquals, where.NotEquals)
    }
    if params.Empty != nil {
        build{{$alias.UpSingular}}QueryWhereParamsNullableFields(params.Empty, where.Empty)
    }
    if params.NotEmpty != nil {
        build{{$alias.UpSingular}}QueryWhereParamsNullableFields(params.NotEmpty, where.NotEmpty)
    }
    if params.In != nil {
        build{{$alias.UpSingular}}QueryWhereParamsInFields(params.In, where.In)
    }
    if params.NotIn != nil {
        build{{$alias.UpSingular}}QueryWhereParamsInFields(params.NotIn, where.NotIn)
    }
    if params.GreaterThan != nil {
        build{{$alias.UpSingular}}QueryWhereParamsComparableFields(params.GreaterThan, where.GreaterThan)
    }
    if params.SmallerThan != nil {
        build{{$alias.UpSingular}}QueryWhereParamsComparableFields(params.SmallerThan, where.SmallerThan)
    }
    if params.SmallerOrEqual != nil {
        build{{$alias.UpSingular}}QueryWhereParamsComparableFields(params.SmallerOrEqual, where.SmallerOrEqual)
    }
    if params.GreaterOrEqual != nil {
        build{{$alias.UpSingular}}QueryWhereParamsComparableFields(params.GreaterOrEqual, where.GreaterOrEqual)
    }
    if params.Like != nil {
        build{{$alias.UpSingular}}QueryWhereParamsLikeFields(params.Like, where.Like)
    }
    if params.NotLike != nil {
        build{{$alias.UpSingular}}QueryWhereParamsLikeFields(params.NotLike, where.NotLike)
    }
}

func build{{$alias.UpSingular}}QueryWhereParamsFields(params *model.{{$alias.UpSingular}}QueryParamsFields, whereFunc func(column string, value any)) {
    toLower := func(column string, isString bool) string {
        if !isString {
             return column
        }

        return fmt.Sprintf("LOWER(%s)", column)
    }

    {{ range $colAlias := getQueryEqColumns .Aliases.Tables $.Tables .Table.Name}}
    {{ $isString := isText $.Aliases.Tables $.Table $colAlias }}
        if !params.{{$colAlias}}.IsNil() {
            whereFunc(toLower({{$alias.UpSingular}}QueryColumns.{{$colAlias}}, {{ $isString }}), {{ if $isString }}types.StringToLower(params.{{$colAlias}}){{ else }}params.{{$colAlias}}{{ end }})
        }
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if params.{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsFields(params.{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
        if params.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsFields(params.LeftJoin{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
    {{end -}}{{- /* range relationships */ -}}
}

func build{{$alias.UpSingular}}QueryWhereParamsNullableFields(params *model.{{$alias.UpSingular}}QueryParamsNullableFields, whereFunc func(column string)) {
    {{- range $colAlias := getQueryNullColumns .Aliases.Tables $.Tables .Table.Name}}
        if params.{{$colAlias}}.Bool() {
            whereFunc({{$alias.UpSingular}}QueryColumns.{{$colAlias}})
        }
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if params.{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsNullableFields(params.{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
        if params.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsNullableFields(params.LeftJoin{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
    {{end -}}{{- /* range relationships */ -}}
}

func build{{$alias.UpSingular}}QueryWhereParamsInFields(params *model.{{$alias.UpSingular}}QueryParamsInFields, whereFunc func(column string, values any)) {
    {{- range $colAlias := getQueryInColumns .Aliases.Tables $.Tables .Table.Name}}
        if params.{{$colAlias}} != nil {
            whereFunc({{$alias.UpSingular}}QueryColumns.{{$colAlias}}, params.{{$colAlias}})
        }
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if params.{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsInFields(params.{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
        if params.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsInFields(params.LeftJoin{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
    {{end -}}{{- /* range relationships */ -}}
}

func build{{$alias.UpSingular}}QueryWhereParamsComparableFields(params *model.{{$alias.UpSingular}}QueryParamsComparableFields, whereFunc func(column string, value any)) {
    {{- range $colAlias := getQueryComparableColumns .Aliases.Tables $.Tables .Table.Name}}
        if !params.{{$colAlias}}.IsNil() {
            whereFunc({{$alias.UpSingular}}QueryColumns.{{$colAlias}}, params.{{$colAlias}})
        }
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if params.{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsComparableFields(params.{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
        if params.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsComparableFields(params.LeftJoin{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
    {{end -}}{{- /* range relationships */ -}}
}

func build{{$alias.UpSingular}}QueryWhereParamsLikeFields(params *model.{{$alias.UpSingular}}QueryParamsLikeFields, whereFunc func(column string, value any)) {
    {{- range $colAlias := getQueryLikeColumns .Aliases.Tables $.Tables .Table.Name}}
        if !params.{{$colAlias}}.IsNil() {
            whereFunc({{$alias.UpSingular}}QueryColumns.{{$colAlias}}, "%" + params.{{$colAlias}}.String() + "%")
        }
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        if params.{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsLikeFields(params.{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
        if params.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
            build{{ $rel.ForeignTable | titleCase }}QueryWhereParamsLikeFields(params.LeftJoin{{ $rel.ForeignTable | titleCase }}, whereFunc)
        }
    {{end -}}{{- /* range relationships */ -}}
}

func build{{$alias.UpSingular}}QueryOffset(q *model.{{$alias.UpSingular}}Query, limiter querybuilder.Limiter) {
    if !q.Offset.IsNil() {
        limiter.Offset(q.Offset.Int())
    }
}

func build{{$alias.UpSingular}}QueryLimit(q *model.{{$alias.UpSingular}}Query, limiter querybuilder.Limiter) {
    if !q.Limit.IsNil() {
        limiter.Limit(q.Limit.Int())
    }
}

func {{$alias.DownSingular}}QueryHasLeftJoin(q *model.{{$alias.UpSingular}}Query) bool {
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if ok := {{$alias.DownSingular}}QueryHasJoinOn{{$relAlias.Local | singular }}(q); ok {
            return true // Load relationships are always left joined
        }
    {{ end }}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if ok := {{$alias.DownSingular}}QueryHasLeftJoinOn{{$relAlias.Local | singular }}(q); ok {
            return true
        }
    {{end }}

    return false
}

{{ range $rel := getLoadRelations $.Tables .Table -}}
{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
func {{$alias.DownSingular}}QueryHasJoinOn{{$relAlias.Local | singular }}(q *model.{{$alias.UpSingular}}Query) bool {
    hasJoin := false

    checkParams := func(p model.{{$alias.UpSingular}}QueryParams) {
        if p.Equals != nil {
            if !p.Equals.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                hasJoin = true
            }
        }
        if p.NotEquals != nil {
            if !p.NotEquals.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                hasJoin = true
            }
        }
        if p.Empty != nil {
            if !p.Empty.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                hasJoin = true
            }
        }
        if p.NotEmpty != nil {
            if !p.NotEmpty.{{ getLoadRelationName $.Aliases $rel | singular }}.IsNil() {
                hasJoin = true
            }
        }
        if p.In != nil {
            if p.In.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
                hasJoin = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.{{ getLoadRelationName $.Aliases $rel | singular }} != nil {
                hasJoin = true
            }
        }
    }

    checkParams(q.Params)

    for _, nested := range q.Nested {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, nested)
    }

    if q.Wrapper != nil {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, *q.Wrapper)
    }

    return hasJoin
}
{{end }}

{{ range $rel := getJoinRelations $.Tables .Table -}}
{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
func {{$alias.DownSingular}}QueryHasJoinOn{{$relAlias.Local | singular }}(q *model.{{$alias.UpSingular}}Query) bool {
    hasJoin := false

    checkParams := func(p model.{{$alias.UpSingular}}QueryParams) {
        if p.Equals != nil {
            if p.Equals.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.NotEquals != nil {
            if p.NotEquals.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.Empty != nil {
            if p.Empty.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.NotEmpty != nil {
            if p.NotEmpty.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.In != nil {
            if p.In.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.GreaterThan != nil {
            if p.GreaterThan.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.SmallerThan != nil {
            if p.SmallerThan.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.SmallerOrEqual != nil {
            if p.SmallerOrEqual.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.GreaterOrEqual != nil {
            if p.GreaterOrEqual.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.Like != nil {
            if p.Like.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
        if p.NotLike != nil {
            if p.NotLike.{{ $rel.ForeignTable | titleCase }} != nil {
                hasJoin = true
            }
        }
    }

    checkParams(q.Params)

    for _, nested := range q.Nested {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, nested)
    }

    if q.Wrapper != nil {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, *q.Wrapper)
    }

    return hasJoin
}

func {{$alias.DownSingular}}QueryHasLeftJoinOn{{$relAlias.Local | singular }}(q *model.{{$alias.UpSingular}}Query) bool {
    hasLeftJoin := false

    checkParams := func(p model.{{$alias.UpSingular}}QueryParams) {
        if p.Equals != nil {
            if p.Equals.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.NotEquals != nil {
            if p.NotEquals.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.Empty != nil {
            if p.Empty.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.NotEmpty != nil {
            if p.NotEmpty.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.In != nil {
            if p.In.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.GreaterThan != nil {
            if p.GreaterThan.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.SmallerThan != nil {
            if p.SmallerThan.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.SmallerOrEqual != nil {
            if p.SmallerOrEqual.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.GreaterOrEqual != nil {
            if p.GreaterOrEqual.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.Like != nil {
            if p.Like.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
        if p.NotLike != nil {
            if p.NotLike.LeftJoin{{ $rel.ForeignTable | titleCase }} != nil {
                hasLeftJoin = true
            }
        }
    }

    checkParams(q.Params)

    for _, nested := range q.Nested {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, nested)
    }

    if q.Wrapper != nil {
    	check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, *q.Wrapper)
    }

    return hasLeftJoin
}
{{end }}

func {{$alias.DownSingular}}QueryHasWhere(q *model.{{$alias.UpSingular}}Query) bool {
    switch {
        case q.HasWrapper(), q.HasNested(), q.Params.IsSet():
            return true
        default:
            return false
    }
}

var all{{$alias.UpSingular}}QueryFields = &model.{{$alias.UpSingular}}QueryFieldsWithOrderBy{
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}}: model.{{$alias.UpSingular}}QueryField{
                Selected: true,
                {{- if isPrimaryKey $.Table $column }}
                    OrderBy: &model.{{$alias.UpSingular}}QueryFieldOrderBy {
                        Index: 0,
                        Desc:  false,
                    },
                {{ else if $column.Name | eq "created_at" }}
                    OrderBy: &model.{{$alias.UpSingular}}QueryFieldOrderBy{
                        Index: 1,
                        Desc:  true,
                    },
                {{- else if hasOrderBy $column }}
                    OrderBy: &model.{{$alias.UpSingular}}QueryFieldOrderBy{
                        Index: {{ getOrderByIndex $column }} + 2, // + 2 because of primary key and created_at are default
                        Desc:  {{ getOrderByDesc $column }},
                    },
                {{- else }}
                    OrderBy: nil,
                {{- end }}
            },
    {{- end}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{ $relAlias.Local | singular }}IDs: true,
    {{end -}}{{- /* range relationships */ -}}
}

func get{{$alias.UpSingular}}ValuesForScan({{$alias.DownSingular}} *model.{{$alias.UpSingular}}, fields *model.{{$alias.UpSingular}}QueryFieldsWithOrderBy) []any {
    values := make([]any, 0)

    {{range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        if fields.{{ $colAlias }}.Selected {
            values = append(values, &{{$alias.DownSingular}}.{{ $colAlias }})
        }
    {{end }}

    return values
}

var {{$alias.UpSingular}}QueryColumns = struct {
	{{range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{$colAlias}} string
	{{end -}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{ getLoadRelationName $.Aliases $rel | singular }} string
    {{end -}}
}{
	{{range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{$colAlias}}: "\"{{$.Table.Name}}\".\"{{$column.Name}}\"",
	{{end -}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
    {{ getLoadRelationName $.Aliases $rel | singular }}: "{{ getLoadRelationTableColumn $.Tables $rel }}",
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
    _ qm.QueryMod
    _ pq.StringArray
)
