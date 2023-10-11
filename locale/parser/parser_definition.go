package parser

import (
	"context"
	"fmt"
	"go/ast"
	"go/token"
	"os"
	"sort"
	"strings"

	"golang.org/x/text/collate"
	"golang.org/x/text/language"
)

func ParseDefinitions(ctx context.Context, filename string) ([]*Definition, error) {
	file, fileset, err := parseFile(ctx, filename)
	if err != nil {
		return nil, err
	}

	var v parserDefinition
	ast.Walk(&v, file)

	collate := collate.New(language.Swedish, collate.IgnoreCase)

	var errors []string

	_ = sort.SliceIsSorted(v.definitions, func(i, j int) bool {
		if collate.CompareString(v.definitions[i].Name, v.definitions[j].Name) == 1 {
			return true
		}

		pos := fileset.Position(token.Pos(v.definitions[i].Position))

		errors = append(errors, fmt.Sprintf("struct %s is not sorted at %s:%d:%d",
			v.definitions[i].Name,
			pos.Filename,
			pos.Line,
			pos.Column,
		))

		return false
	})

	if len(errors) > 0 {
		fmt.Fprintf(os.Stderr, "structs are not alphabetically sorted:\n%s\n", strings.Join(errors, "\n"))
		os.Exit(1)
	}

	for _, s := range v.definitions {
		_ = sort.SliceIsSorted(s.Fields, func(i, j int) bool {
			if collate.CompareString(s.Fields[i].Name, s.Fields[j].Name) == 1 {
				return true
			}

			pos := fileset.Position(token.Pos(s.Fields[i].Position))

			errors = append(errors, fmt.Sprintf("field %s for struct %s is not sorted at %s:%d:%d",
				s.Fields[i].Name,
				s.Name,
				pos.Filename,
				pos.Line,
				pos.Column,
			))

			return false
		})
	}

	if len(errors) > 0 {
		fmt.Fprintf(os.Stderr, "Fields are not alphabetically sorted:\n%s\n", strings.Join(errors, "\n"))
		os.Exit(1)
	}

	return v.definitions, nil
}

type parserDefinition struct {
	definitions []*Definition
}

type Definition struct {
	Position int
	Name     string
	Fields   []DefinitionField
}

type DefinitionField struct {
	Position int
	Name     string
	Tag      string
	Typ      string
}

func (v *parserDefinition) Visit(node ast.Node) ast.Visitor {
	if node == nil {
		return nil
	}

	switch n := node.(type) {
	case *ast.TypeSpec:
		if !strings.HasPrefix(n.Name.Name, Locale) {
			panic("unexpected type Name")
			return nil
		}

		switch n.Name.Name {
		case LocaleKey, LocaleKeySchoolType:
			return nil
		}

		structType, ok := n.Type.(*ast.StructType)
		if !ok {
			panic("unexpected type")
		}

		definition := Definition{
			Position: int(structType.Pos()),
			Name:     n.Name.Name,
			Fields:   nil,
		}

		for _, field := range structType.Fields.List {
			typ, ok := field.Type.(*ast.Ident)
			if !ok {
				panic("unexpected type")
			}

			typName := typ.Name

			// We want to use string instead of LocaleKey in the generated code
			if typName == LocaleKey {
				typName = "string"
			}

			definition.Fields = append(definition.Fields, DefinitionField{
				Position: int(field.Pos()),
				Name:     field.Names[0].Name,
				Tag:      field.Tag.Value,
				Typ:      typName,
			})
		}

		v.definitions = append(v.definitions, &definition)
	}

	return v
}
