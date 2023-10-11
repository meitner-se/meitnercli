package parser

import (
	"fmt"
	"go/token"
	"sort"
	"strings"

	"golang.org/x/text/collate"
	"golang.org/x/text/language"

	"github.com/friendsofgo/errors"
)

func validateFields(fileset *token.FileSet, fields []ObjectField) error {
	errs := make([]string, 0)

	validateFieldsAreSet(fileset, &errs, fields)
	validateFieldsAlphabeticallyOrdered(fileset, &errs, fields)
	validateFieldsParams(fileset, &errs, fields)

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "\n"))
	}

	return nil
}

func validateFieldsAlphabeticallyOrdered(fileset *token.FileSet, errors *[]string, fields []ObjectField) {
	collate := collate.New(language.Swedish, collate.IgnoreCase)

	_ = sort.SliceIsSorted(fields, func(i, j int) bool {
		if collate.CompareString(fields[i].Name, fields[j].Name) == 1 {
			return true
		}

		pos := fileset.Position(token.Pos(fields[i].Position))

		*errors = append(*errors, fmt.Sprintf("field %s is not sorted at %s:%d:%d",
			fields[i].Name,
			pos.Filename,
			pos.Line,
			pos.Column,
		))

		return false
	})
}

func validateFieldsAreSet(fileset *token.FileSet, errors *[]string, fields []ObjectField) {
	for _, field := range fields {
		if field.Object != nil {
			validateFieldsAreSet(fileset, errors, field.Object.Fields)
			continue
		}

		pos := fileset.Position(token.Pos(field.Position))

		if field.ObjectFieldValue.English == emptyString {
			*errors = append(*errors, fmt.Sprintf("field %s is not set for english at %s:%d:%d",
				field.Name,
				pos.Filename,
				pos.Line,
				pos.Column,
			))
		}

		if field.ObjectFieldValue.Swedish == emptyString {
			*errors = append(*errors, fmt.Sprintf("field %s is not set for swedish at %s:%d:%d",
				field.Name,
				pos.Filename,
				pos.Line,
				pos.Column,
			))
		}

		if field.ObjectFieldValue.Preschool != nil {
			if field.ObjectFieldValue.Preschool.English == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for preschool english at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}

			if field.ObjectFieldValue.Preschool.Swedish == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for preschool swedish at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}

		if field.ObjectFieldValue.Elementary != nil {
			if field.ObjectFieldValue.Elementary.English == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for elementary english at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}

			if field.ObjectFieldValue.Elementary.Swedish == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for elementary swedish at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}

		if field.ObjectFieldValue.UpperSecondary != nil {
			if field.ObjectFieldValue.UpperSecondary.English == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for upper-secondary english at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}

			if field.ObjectFieldValue.UpperSecondary.Swedish == emptyString {
				*errors = append(*errors, fmt.Sprintf("field %s is not set for upper-secondary swedish at %s:%d:%d",
					field.Name,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}
	}
}

func validateFieldsParams(fileset *token.FileSet, errors *[]string, fields []ObjectField) {
	for _, field := range fields {
		if field.ObjectFieldValue == nil {
			validateFieldsParams(fileset, errors, field.Object.Fields)
			continue
		}

		pos := fileset.Position(token.Pos(field.Position))

		for _, englishParam := range field.ObjectFieldValue.englishParams {
			if !strings.Contains(field.ObjectFieldValue.Swedish, "{{"+englishParam+"}}") {
				*errors = append(*errors, fmt.Sprintf("inconsistent params for field %s - swedish does not contain english param: %s at %s:%d:%d",
					field.Name,
					englishParam,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}

		for _, swedishParam := range field.ObjectFieldValue.swedishParams {
			if !strings.Contains(field.ObjectFieldValue.English, "{{"+swedishParam+"}}") {
				*errors = append(*errors, fmt.Sprintf("inconsistent params for field %s - english does not contain swedish param: %s at %s:%d:%d",
					field.Name,
					swedishParam,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}

		for _, param := range field.ObjectFieldValue.Params() {
			if isReservedWord(param) {
				*errors = append(*errors, fmt.Sprintf("reserved word used as param for field %s: %s at %s:%d:%d",
					field.Name,
					param,
					pos.Filename,
					pos.Line,
					pos.Column,
				))
			}
		}
	}
}

func isReservedWord(str string) bool {
	switch str {
	case "type":
		return true
	default:
		return false
	}
}
