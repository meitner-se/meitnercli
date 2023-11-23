{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
func TestGet{{ $alias.UpSingular }}(t *testing.T) {
	ctx := context.Background()
	base := setup(t)

    {{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, base.schoolAdminServices.{{ getServiceName | titleCase }}Service, func(request *client.{{ $alias.UpSingular }}CreateRequest) {
        // TODO : manipulate the request if needed, otherwise pass nil instead of this function
    })

    request := client.{{ $alias.UpSingular }}GetRequest{
        ID: {{ $alias.DownSingular }}.ID,
    }

    t.Run("cannot get non existing {{ $alias.DownSingular }}", func(t *testing.T) {
        invalidRequest := request
        invalidRequest.ID = types.NewRandomUUID()

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Get{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })

    t.Run("cannot get {{ $alias.DownSingular }} from other school", func(t *testing.T) {
        otherBase := setup(t)
        other{{ $alias.UpSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, otherBase.schoolAdminServices.{{ getServiceName | titleCase }}Service, nil)

        invalidRequest := request
        invalidRequest.ID = other{{ $alias.UpSingular }}.ID

        _, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Get{{ $alias.UpSingular }}(ctx, invalidRequest)
        test_helpers.AssertErr(t, err, errors.NotFound, "cannot find {{ $alias.DownSingular }}")
    })

    t.Run("success", func(t *testing.T) {
        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.Get{{ $alias.UpSingular }}(ctx, request)
        require.NoError(t, err)
        assert.NotNil(t, response)
        assert.Equal(t, {{ $alias.DownSingular }}, response.{{ $alias.UpSingular }})
    })
}

func TestList{{ $alias.UpSingular }}(t *testing.T) {
	ctx := context.Background()
	base := setup(t)

    {{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, base.schoolAdminServices.{{ getServiceName | titleCase }}Service, func(request *client.{{ $alias.UpSingular }}CreateRequest) {
        // TODO : manipulate the request if needed, otherwise pass nil instead of this function
    })

    request := client.{{ $alias.UpSingular }}ListRequest{}

    t.Run("cannot list {{ $alias.DownPlural }} from other school", func(t *testing.T) {
        otherBase := setup(t)
        other{{ $alias.UpSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, otherBase.schoolAdminServices.{{ getServiceName | titleCase }}Service, nil)

        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.List{{ $alias.UpPlural }}(ctx, request)
        require.NoError(t, err)
        assert.NotNil(t, response)
        assert.NotContains(t, response.{{ $alias.UpPlural }}, other{{ $alias.UpSingular }})
    })

    t.Run("success", func(t *testing.T) {
        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.List{{ $alias.UpPlural }}(ctx, request)
        require.NoError(t, err)
        assert.NotNil(t, response)
        if assert.Len(t, response.{{ $alias.UpPlural }}, 1) {
            assert.Contains(t, response.{{ $alias.UpPlural }}, {{ $alias.DownSingular }})
        }
    })
}

func TestList{{ $alias.UpSingular }}ByIDs(t *testing.T) {
	ctx := context.Background()
	base := setup(t)

    {{ $alias.DownSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, base.schoolAdminServices.{{ getServiceName | titleCase }}Service, func(request *client.{{ $alias.UpSingular }}CreateRequest) {
        // TODO : manipulate the request if needed, otherwise pass nil instead of this function
    })

    request := client.{{ $alias.UpSingular }}ListByIDsRequest{
        IDs: []types.UUID{
            {{ $alias.DownSingular }}.ID,
        },
    }

    t.Run("cannot list non existing {{ $alias.DownPlural }}", func(t *testing.T) {
        invalidRequest := request
        invalidRequest.IDs = []types.UUID{
            types.NewRandomUUID(),
        }

        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.List{{ $alias.UpPlural }}ByIDs(ctx, invalidRequest)
        require.NoError(t, err)
        assert.NotNil(t, response)
        assert.Empty(t, response.{{ $alias.UpPlural }})
    })

    t.Run("cannot list {{ $alias.DownPlural }} from other school", func(t *testing.T) {
        otherBase := setup(t)
        other{{ $alias.UpSingular }}, _ := test_helpers.Create{{ $alias.UpSingular }}(t, otherBase.schoolAdminServices.{{ getServiceName | titleCase }}Service, nil)

        invalidRequest := request
        invalidRequest.IDs = []types.UUID{
            other{{ $alias.UpSingular }}.ID,
        }

        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.List{{ $alias.UpPlural }}ByIDs(ctx, invalidRequest)
        require.NoError(t, err)
        assert.NotNil(t, response)
        assert.Empty(t, response.{{ $alias.UpPlural }})
    })

    t.Run("success", func(t *testing.T) {
        response, err := base.schoolAdminServices.{{ getServiceName | titleCase }}Service.List{{ $alias.UpPlural }}ByIDs(ctx, request)
        require.NoError(t, err)
        assert.NotNil(t, response)
        if assert.Len(t, response.{{ $alias.UpPlural }}, 1) {
            assert.Contains(t, response.{{ $alias.UpPlural }}, {{ $alias.DownSingular }})
        }
    })
}
{{end -}}

// we can't avoid importing types when creating integration tests stubs, so we add a safeguard
// the variable and import can be removed
var _ = types.NewTimestamp
// strconv is usually not used in tests so the import and the variable can be removed
var _ = strconv.IntSize
