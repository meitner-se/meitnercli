// Query_{{ titleCase .PkgName }}Service is the API to read states of the {{ titleCase .PkgName }}Service
type Query_{{ titleCase .PkgName }}Service interface {
{{- range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        // Get{{$alias.UpSingular}} gets the {{$alias.UpSingular}}-entity by the given params
        //
        // TODO : permissions ?
        Get{{$alias.UpSingular}}({{$alias.UpSingular}}GetRequest) {{$alias.UpSingular}}GetResponse
        
        // List{{$alias.UpPlural}} lists the {{$alias.UpSingular}}-entities by the given params
        //
        // TODO : permissions ?
        List{{$alias.UpPlural}}({{$alias.UpSingular}}ListRequest) {{$alias.UpSingular}}ListResponse

        // List{{$alias.UpPlural}}ByIDs lists the {{$alias.UpSingular}}-entities by the given IDs
        //
        // TODO : permissions ?
        List{{$alias.UpPlural}}ByIDs({{$alias.UpSingular}}ListByIDsRequest) {{$alias.UpSingular}}ListByIDsResponse
    {{ end }}
{{ end }}
}

{{range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        {{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
        {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

        // {{$alias.UpSingular}}GetRequest is the input object for getting an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}GetRequest struct {
            {{- range $pkName := $pkNames }}
                // type: "types.UUID"
                {{ $pkName }} string
            {{ end }}
        }

        // {{$alias.UpSingular}}GetResponse is the output object for getting an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}GetResponse struct {
            {{$alias.UpSingular}} {{$alias.UpSingular}}
        }

        // {{$alias.UpSingular}}ListRequest is the input object for listing {{$alias.UpSingular}}-entities
        type {{$alias.UpSingular}}ListRequest struct {
            Query {{$alias.UpSingular}}QueryRequest
        }

        // {{$alias.UpSingular}}ListResponse is the output object for listing {{$alias.UpSingular}}-entities
        type {{$alias.UpSingular}}ListResponse struct {
            // type: "types.Int64"
            TotalCount int64
            {{$alias.UpPlural}} []{{$alias.UpSingular}}
        }

        // {{$alias.UpSingular}}ListByIDsRequest is the input object for listing {{$alias.UpSingular}}-entities by IDs
        type {{$alias.UpSingular}}ListByIDsRequest struct {
            // type: "types.UUID"
            IDs []string
        }

        // {{$alias.UpSingular}}ListByIDsResponse is the output object for listing {{$alias.UpSingular}}-entities by IDs
        type {{$alias.UpSingular}}ListByIDsResponse struct {
            {{$alias.UpPlural}} []{{$alias.UpSingular}}
        }
    {{ end }}
{{ end }}
