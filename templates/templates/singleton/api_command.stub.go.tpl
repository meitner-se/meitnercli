// Command_{{ titleCase .PkgName }}Service is the API to perform state changes of the {{ titleCase .PkgName }}Service
type Command_{{ titleCase .PkgName }}Service interface {
{{- range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}

        // Create{{$alias.UpSingular}} creates a new {{$alias.UpSingular}}-entity
        //
        // TODO : permissions ?
        Create{{$alias.UpSingular}}({{$alias.UpSingular}}CreateRequest) {{$alias.UpSingular}}CreateResponse
        // Update{{$alias.UpSingular}} updates an existing {{$alias.UpSingular}}-entity
        //
        // TODO : permissions ?
        Update{{$alias.UpSingular}}({{$alias.UpSingular}}UpdateRequest) {{$alias.UpSingular}}UpdateResponse
        // Delete{{$alias.UpSingular}} deletes the given {{$alias.UpSingular}}-entity
        //
        // TODO : permissions ?
        Delete{{$alias.UpSingular}}({{$alias.UpSingular}}DeleteRequest) {{$alias.UpSingular}}DeleteResponse

    {{ end }}
{{ end }}
}

{{range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        {{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
        {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

        // {{$alias.UpSingular}}CreateRequest is the input object for creating a new {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}CreateRequest struct {
        	{{- range $column := $table.Columns -}}
            {{- if not (or (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
            {{- $colAlias := $alias.Column $column.Name -}}
            {{- $orig_col_name := $column.Name -}}

            {{- if not (containsAny $pkNames $colAlias ) -}}

            {{- range $column.Comment | splitLines }} // {{ . }} {{ end -}}
            {{- if .Nullable -}} // nullable: true {{- end -}}

            {{- if (isEnumDBType .DBType) }}
                // options: [{{- parseEnumVals $column.DBType | stringMap $.StringFuncs.quoteWrap | join ", " -}}]
                // type: "types.String"
                {{$colAlias}} {{ if $column.Nullable }}*{{ end }}string
            {{ else }}
                // type: "{{$column.Type}}"
                {{$colAlias}} 

                {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Time, types.Date" -}}
                {{- if contains $column.Type $stringTypes -}}
                    {{" "}}{{ if $column.Nullable }}*{{ end }}string
                {{end -}}

                {{- if eq $column.Type "types.Bool" -}}
                    {{" "}}{{ if $column.Nullable }}*{{ end }}bool
                {{end -}}

                {{- if contains "types.Int" $column.Type -}}
                    {{" "}}{{ if $column.Nullable }}*{{ end }}int
                {{end -}}

                {{- if contains "JSON" $column.Type -}}
                    {{" "}}{{ if $column.Nullable }}*{{ end }}interface{}
                {{end -}}

            {{- end }}
            {{- end }}
            {{- end }}
            {{ end }}

            {{- range $rel := getLoadRelations $.Tables $table }}
                {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
                // type: "types.UUID"
                {{ $relAlias.Local | singular }}IDs []string
            {{end }}
        }

        // {{$alias.UpSingular}}CreateResponse is the output object for creating a new {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}CreateResponse struct {
            Created {{$alias.UpSingular}}
        }

        // {{$alias.UpSingular}}UpdateRequest is the input object for updating an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}UpdateRequest struct {
            {{- range $column := $table.Columns -}}
            {{- if not (or (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
            {{- $colAlias := $alias.Column $column.Name -}}
            {{- $orig_col_name := $column.Name -}}
            
            {{ range $column.Comment | splitLines }} // {{ . }} {{ end -}}
            {{ if .Nullable }} // nullable: true {{ end -}}

            {{ if containsAny $pkNames $colAlias }}
                // type: "types.UUID"
                {{$colAlias}} string
            {{ else if (isEnumDBType .DBType) -}}
                // optional: true
                // options: [{{- parseEnumVals $column.DBType | stringMap $.StringFuncs.quoteWrap | join ", " -}}]
                // type: "types.String"
                {{$colAlias}} *string
            {{ else }}
                // optional: true
                // type: "{{$column.Type}}"
                {{$colAlias}} 
            
                {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Time, types.Date" -}}
                {{- if contains $column.Type $stringTypes -}}
                    {{" "}}{{ if not (containsAny $pkNames $colAlias) }}*{{ end }}string
                {{end -}}

                {{- if eq $column.Type "types.Bool" -}}
                    {{" "}} *bool
                {{end -}}

                {{- if contains "types.Int" $column.Type -}}
                    {{" "}} *int
                {{end -}}

                {{- if contains "JSON" $column.Type -}}
                    {{" "}} *interface{}
                {{end -}}
            
            {{- end }}
            {{- end }}
            {{ end }}

            {{- range $rel := getLoadRelations $.Tables $table -}}
                {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
                // type: "types.UUID"
                {{ $relAlias.Local | singular }}IDs []string
            {{end -}}{{- /* range relationships */ -}}
        }

        // {{$alias.UpSingular}}UpdateResponse is the output object for updating an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}UpdateResponse struct{
            Updated {{$alias.UpSingular}}
        }

        // {{$alias.UpSingular}}DeleteRequest is the input object for deleting an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}DeleteRequest struct {
            {{- range $pkNames}}
                // type: "types.UUID"
                {{ . }} string
            {{ end}}
        }

        // {{$alias.UpSingular}}DeleteResponse is the output object for deleting an existing {{$alias.UpSingular}}-entity
        type {{$alias.UpSingular}}DeleteResponse struct{}
    {{ end }}
{{ end }}
