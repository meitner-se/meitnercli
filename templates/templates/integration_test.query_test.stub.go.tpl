{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
func TestGet{{ $alias.UpSingular }}(t *testing.T) {
    r := require.New(t)
    a := assert.New(t)
	ctx := context.Background()

	base := setup(t)

	{{ $alias.DownSingular }}, createReq := test_helpers.Create{{ $alias.UpSingular }}(ctx)
	getRes, err := base.{{getServiceName }}Service.Get{{ $alias.UpSingular }}(ctx, client.{{ $alias.UpSingular }}GetRequest{ID: {{ $alias.DownSingular }}.ID})
	r.NoError(err)

    {{range $column := .Table.Columns }}
    {{- if not (or (eq $column.Name "id") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        a.Equal(createReq.{{ $colAlias }}, getRes.{{ $alias.UpSingular }}.{{ $colAlias }})
    {{end -}}
    {{- end -}}
}

func TestList{{ $alias.UpSingular }}(t *testing.T) {
    r := require.New(t)
    a := assert.New(t)
	ctx := context.Background()

	base := setup(t)

	{{ $alias.DownSingular }}, createReq := test_helpers.Create{{ $alias.UpSingular }}(ctx)
	listRes, err := base.{{getServiceName }}Service.List{{ $alias.UpPlural }}(ctx, client.{{ $alias.UpSingular }}ListRequest{})
	r.NoError(err)

    if a.Len(listRes.{{ $alias.UpPlural }}, 1){
    {{range $column := .Table.Columns }}
    {{- if not (or (eq $column.Name "id") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        a.Equal(createReq.{{ $colAlias }}, listRes.{{ $alias.UpPlural }}[0].{{ $colAlias }})
    {{end -}}
    {{- end -}}
    }
}

func TestList{{ $alias.UpSingular }}ByIDs(t *testing.T) {
    r := require.New(t)
    a := assert.New(t)
	ctx := context.Background()

	base := setup(t)

	{{ $alias.DownSingular }}, createReq := test_helpers.Create{{ $alias.UpSingular }}(ctx)
	listRes, err := base.{{getServiceName }}Service.List{{ $alias.UpPlural }}ByIDs(ctx, client.{{ $alias.UpSingular }}ListByIDsRequest{IDs: []types.UUID{ {{ $alias.DownSingular }}.ID}})
	r.NoError(err)

    if a.Len(listRes.{{ $alias.UpPlural }}, 1){
    {{range $column := .Table.Columns }}
    {{- if not (or (eq $column.Name "id") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        a.Equal(createReq.{{ $colAlias }}, listRes.{{ $alias.UpPlural }}[0].{{ $colAlias }})
    {{end -}}
    {{- end -}}
    }
}
{{end -}}

// we can't avoid importing types when creating integration tests stubs, so we add a safeguard
// the variable and import can be removed
var _ = types.NewTimestamp
// strconv is usually not used in tests so the import and the variable can be removed
var _ = strconv.IntSize
