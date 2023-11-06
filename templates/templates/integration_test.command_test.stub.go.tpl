{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
func TestCreate{{ $alias.UpSingular }}(t *testing.T) {
    r := require.New(t)
    // a := assert.New(t)
	ctx := context.Background()

	base := setup(t)

	createRes, err := base.{{getServiceName }}Service.Create{{ $alias.UpSingular }}(ctx, client.{{ $alias.UpSingular }}CreateRequest{
    {{range $column := .Table.Columns }}
    {{- if not (or (eq $column.Name "id")  (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{ if eq $column.Type "types.String" -}}
            {{$colAlias}}: test_helpers.RandomString(){{ if $column.Nullable }}.Ptr(){{ end }},
            {{ else if eq $column.Type "types.Date" -}}
            {{$colAlias}}: test_helpers.RandomDate(){{ if $column.Nullable }}.Ptr(){{ end }},
            {{ else if eq $column.Type "types.Time" -}}
            {{$colAlias}}: test_helpers.RandomTime(){{ if $column.Nullable }}.Ptr(){{ end }},
            {{ else if eq $column.Type "types.Timestamp" -}}
            {{$colAlias}}: test_helpers.RandomTimestamp(){{ if $column.Nullable }}.Ptr(){{ end }},
            {{ else if eq $column.Type "types.Int" -}}
            {{$colAlias}}: test_helpers.RandomIntRange(0, 100){{ if $column.Nullable }}.Ptr(){{ end }},
            {{ else if eq $column.Type "types.UUID" -}}
            {{$colAlias}}: nil, // TODO: fix UUID
            {{ else -}}
            {{$colAlias}}: nil,
            {{ end -}}
    {{end -}}
    {{- end -}}
	})
	r.NoError(err)
}

func TestUpdate{{ $alias.UpSingular }}(t *testing.T) {
    {{- $alias := $.Aliases.Table .Table.Name -}}
    {{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
    {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}
    r := require.New(t)
    // a := assert.New(t)
	ctx := context.Background()

	base := setup(t)

	{{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(ctx)

	_, err := base.{{getServiceName }}Service.Update{{ $alias.UpSingular }}(ctx, client.{{ $alias.UpSingular }}UpdateRequest{
        {{ range $column := .Table.Columns -}}
        {{- if not (or (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- $orig_col_name := $column.Name -}}
            {{- if eq $column.Name "id" -}}
            {{$colAlias}}: {{ $alias.DownSingular }}.ID,
            {{ else if eq $column.Type "types.String" -}}
            {{$colAlias}}: test_helpers.RandomString().Ptr(),
            {{ else if eq $column.Type "types.Date" -}}
            {{$colAlias}}: test_helpers.RandomDate().Ptr(),
            {{ else if eq $column.Type "types.Time" -}}
            {{$colAlias}}: test_helpers.RandomTime().Ptr(),
            {{ else if eq $column.Type "types.Timestamp" -}}
            {{$colAlias}}: test_helpers.RandomTimestamp().Ptr(),
            {{ else if eq $column.Type "types.Int" -}}
            {{$colAlias}}: test_helpers.RandomIntRange(0, 100).Ptr(),
            {{ else if eq $column.Type "types.UUID" -}}
            {{$colAlias}}: nil, // TODO: fix UUID
            {{ else -}}
            {{$colAlias}}: nil,
            {{ end -}}
        {{ end -}}
        {{end -}}
	})
	r.NoError(err)
}

func TestDelete{{ $alias.UpSingular }}(t *testing.T) {
    r := require.New(t)
	ctx := context.Background()

	base := setup(t)

	{{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(ctx)

	_, err := base.{{getServiceName }}Service.Delete{{ $alias.UpSingular }}(ctx, client.{{ $alias.UpSingular }}DeleteRequest{ID: {{ $alias.DownSingular }}.ID})
	r.NoError(err)
}
{{end -}}

// we can't avoid importing types when creating integration tests stubs, so we add a safeguard
// the variable and import can be removed
var _ = types.NewTimestamp
// strconv is usually not used in tests so the import and the variable can be removed
var _ = strconv.IntSize
