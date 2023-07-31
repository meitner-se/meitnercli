type queryService interface {
{{ range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        {{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
        {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.camelCase | stringMap $.StringFuncs.replaceReserved -}}
        {{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}

        Get{{ $alias.UpSingular }}(ctx context.Context, {{ $pkArgs }}) (*model.{{ $alias.UpSingular }}, error)
        List{{ $alias.UpPlural }}(ctx context.Context, query model.{{ $alias.UpSingular }}Query) ([]*model.{{ $alias.UpSingular }}, *types.Int64, error)

    {{ end }}
{{ end }}
}

var _ api.Query_{{getServiceName | titleCase }}Service = (*query)(nil)

type query struct {
    svc queryService
}

func NewQueryEndpoint(svc queryService) *query {
    return &query{
        svc: svc,
    }
}

{{ range $table := .Tables}}
{{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
{{- $alias := $.Aliases.Table $table.Name -}}
{{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

func (q *query) Get{{$alias.UpSingular}}(ctx context.Context, r api.{{$alias.UpSingular}}GetRequest) (*api.{{$alias.UpSingular}}GetResponse, error) {
    {{$alias.DownSingular}}, err := q.svc.Get{{ $alias.UpSingular }}(ctx, {{ prefixStringSlice "r." $pkNames | join ", "}})
    if err != nil {
        return nil, err
    }

    {{ if tableHasFile $table }} // TODO : Implement file url resolver in conversion {{end}}

    return &api.{{$alias.UpSingular}}GetResponse{
        {{$alias.UpSingular}}: conversion.{{$alias.UpSingular}}FromModel({{$alias.DownSingular}} {{ if tableHasFile $table }}, nil {{end}}),
    }, nil
}

func (q *query) List{{$alias.UpPlural}}(ctx context.Context, r api.{{$alias.UpSingular}}ListRequest) (*api.{{$alias.UpSingular}}ListResponse, error) {
    {{$alias.DownPlural}}, totalCount, err := q.svc.List{{ $alias.UpPlural }}(ctx, conversion.{{$alias.UpSingular}}QueryToModel(r.Query, nil))
    if err != nil {
        return nil, err
    }

    {{ if tableHasFile $table }} // TODO : Implement file url resolver in conversion {{end}}

    return &api.{{$alias.UpSingular}}ListResponse{
        TotalCount: *totalCount,
        {{$alias.UpPlural}}: conversion.{{$alias.UpSingular}}FromModels({{$alias.DownPlural}} {{ if tableHasFile $table }}, nil {{end}}),
    }, nil
}

func (q *query) List{{$alias.UpPlural}}ByIDs(ctx context.Context, r api.{{$alias.UpSingular}}ListByIDsRequest) (*api.{{$alias.UpSingular}}ListByIDsResponse, error) {
    {{$alias.DownPlural}} := make([]*model.{{$alias.UpSingular}}, 0, len(r.IDs))

    for _, id := range r.IDs {
        {{$alias.DownSingular}}, err := q.svc.Get{{$alias.UpSingular}}(ctx, id)
        if errors.IsNotFound(err) {
        	continue
        }
        if err != nil {
            return nil, errors.Wrap(err, "cannot get user")
        }

        {{$alias.DownPlural}} = append({{$alias.DownPlural}}, {{$alias.DownSingular}})
    }

    {{ if tableHasFile $table }} // TODO : Implement file url resolver in conversion {{end}}

    return &api.{{$alias.UpSingular}}ListByIDsResponse{
        {{$alias.UpPlural}}: conversion.{{$alias.UpSingular}}FromModels(model.Sort{{$alias.UpPlural}}({{$alias.DownPlural}}) {{ if tableHasFile $table }}, nil {{end}}),
    }, nil
}

{{ end }}
{{ end }}
