package parser

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"

	"github.com/friendsofgo/errors"
)

const (
	LocaleVariableName  string = "locale"
	Locale              string = "Locale"
	LocaleKey           string = "LocaleKey"
	LocaleKeySchoolType string = "LocaleKeySchoolType"

	English string = "English"
	Swedish string = "Swedish"

	Preschool      string = "Preschool"
	Elementary     string = "Elementary"
	UpperSecondary string = "UpperSecondary"

	emptyString = "\"\""
)

func parseFile(ctx context.Context, filename string) (*ast.File, *token.FileSet, error) {
	fileset := token.NewFileSet() // positions are relative to fileset

	// Parse src but stop after processing the imports.
	file, err := parser.ParseFile(fileset, filename, nil, parser.AllErrors)
	if err != nil {
		return nil, nil, errors.Wrap(err, "cannot parse file")
	}

	if len(file.Imports) > 0 {
		return nil, nil, errors.New("no imports allowed")
	}

	return file, fileset, nil
}
