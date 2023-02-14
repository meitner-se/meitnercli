// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Replace ".stub" with ".def" in the filename and delete the comments above, included the top disclaimer.

// _query_{{ titleCase .PkgName }}Service is the API to read states of the {{ titleCase .PkgName }}Service
type _query_{{ titleCase .PkgName }}Service interface {
{{ range $table := .Tables}}
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
            {{$alias.UpPlural}}TotalCount int64
            {{$alias.UpPlural}} []{{$alias.UpSingular}}
        }
    {{ end }}
{{ end }}

var _ _query_{{ titleCase .PkgName }}Service // make sure interface is used to prevent staticcheck to error
