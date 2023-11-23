{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
func TestCreate{{ $alias.UpSingular }}(t *testing.T) {
	ctx := context.Background()
	base := setup(t)

	request := client.{{ $alias.UpSingular }}CreateRequest{
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
    }

	t.Run("success", func(t *testing.T) {
		response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.CreatePlan(ctx, request)
		require.NoError(t, err)
		assert.NotEmpty(t, response.ID)
	})
}

func TestUpdate{{ $alias.UpSingular }}(t *testing.T) {
    {{- $alias := $.Aliases.Table .Table.Name -}}
    {{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
    {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}
	ctx := context.Background()
	base := setup(t)

	{{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, base.schoolAdminServices.{{ getServiceName | titleCase }}Service, func(request *client.{{ $alias.UpSingular }}CreateRequest) {
        // TODO : manipulate the request if needed, otherwise pass nil instead of this function
    })

	request := client.{{ $alias.UpSingular }}UpdateRequest{
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
    }

    t.Run("cannot update non existing {{ $alias.DownSingular }}", func(t *testing.T) {
        invalidRequest := request
        invalidRequest.ID = types.NewRandomUUID()

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Update{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })

    t.Run("cannot update {{ $alias.DownSingular }} from other school", func(t *testing.T) {
        otherBase := setup(t)
        other{{ $alias.UpSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, otherBase.schoolAdminServices.{{ getServiceName | titleCase }}Service, nil)

        invalidRequest := request
        invalidRequest.ID = other{{ $alias.UpSingular }}.ID

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Update{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })


    t.Run("success", func(t *testing.T) {
    	_, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Update{{ $alias.UpSingular }}(ctx, request)
    	require.NoError(t, err)

    	getRequest := client.{{ $alias.UpSingular }}GetRequest{
    	    ID: {{ $alias.DownSingular }}.ID,
        }

        getResponse, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.GetPlan(ctx, getRequest)
        require.NoError(t, err)
        {{range $column := .Table.Columns }}
        {{- if not (or (eq $column.Name "id") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
            {{- $colAlias := $alias.Column $column.Name -}}
            assert.Equal(t, request.{{ $colAlias }}, getResponse.{{ $alias.UpSingular }}.{{ $colAlias }})
        {{end -}}
        {{- end -}}
    })
}

func TestDelete{{ $alias.UpSingular }}(t *testing.T) {
	ctx := context.Background()
	base := setup(t)

	{{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, base.schoolAdminServices.{{ getServiceName | titleCase }}Service, func(request *client.{{ $alias.UpSingular }}CreateRequest) {
        // TODO : manipulate the request if needed, otherwise pass nil instead of this function
    })

	request := client.{{ $alias.UpSingular }}DeleteRequest{
	    ID: {{ $alias.DownSingular }}.ID,
	}

    t.Run("cannot delete non existing {{ $alias.DownSingular }}", func(t *testing.T) {
        invalidRequest := request
        invalidRequest.ID = types.NewRandomUUID()

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Delete{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })

    t.Run("cannot delete {{ $alias.DownSingular }} from other school", func(t *testing.T) {
        otherBase := setup(t)
        other{{ $alias.UpSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, otherBase.schoolAdminServices.{{ getServiceName | titleCase }}Service, nil)

        invalidRequest := request
        invalidRequest.ID = other{{ $alias.UpSingular }}.ID

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Delete{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })

    t.Run("success", func(t *testing.T) {
        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Delete{{ $alias.UpSingular }}(ctx, request)
        require.NoError(t, err)

        getRequest := client.{{ $alias.UpSingular }}GetRequest{
            ID: {{ $alias.DownSingular }}.ID,
        }

        _, err = base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Get{{ $alias.UpSingular }}(ctx, getRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })
}
{{end -}}

// we can't avoid importing types when creating integration tests stubs, so we add a safeguard
// the variable and import can be removed
var _ = types.NewTimestamp
// strconv is usually not used in tests so the import and the variable can be removed
var _ = strconv.IntSize
