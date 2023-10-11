package parser

import (
	"context"
	"fmt"
	"go/ast"
	"go/token"
	"log/slog"
	"regexp"
	"strings"

	"github.com/friendsofgo/errors"
)

var extractParamsRegexp = regexp.MustCompile(`{{\s*(\w+)\s*}}`)

type Object struct {
	Name   string
	Fields []ObjectField
}

type ObjectField struct {
	Position         int
	Name             string
	Tag              string
	TagNested        string
	Object           *Object
	ObjectFieldValue *ObjectFieldValue
}

type ObjectFieldValue struct {
	English        string
	Swedish        string
	Preschool      *ObjectFieldValueSchoolType
	Elementary     *ObjectFieldValueSchoolType
	UpperSecondary *ObjectFieldValueSchoolType

	englishParams []string
	swedishParams []string
}

type ObjectFieldValueSchoolType struct {
	English string
	Swedish string
}

func ParseValues(ctx context.Context, definitions []*Definition, filename string, skipValidation bool) (*Object, error) {
	slog.Info("START Parse Values")
	defer slog.Info("FINISH Parse Values")

	file, fileset, err := parseFile(ctx, filename)
	if err != nil {
		return nil, err
	}

	v := localeValueVisitor{
		definitions: definitions,
	}

	ast.Walk(&v, file)

	if !skipValidation {
		err = validateFields(fileset, v.locale.Fields)
		if err != nil {
			return nil, err
		}
	}

	return &v.locale, nil
}

type localeValueVisitor struct {
	locale      Object
	definitions []*Definition
}

func (v *localeValueVisitor) Visit(node ast.Node) ast.Visitor {
	if node == nil {
		return nil
	}

	valueSpec, ok := node.(*ast.ValueSpec)
	if !ok {
		return v
	}

	// Only the locale-variable is allowed
	if valueSpec.Names[0].Name != LocaleVariableName {
		panic("unexpected type Name")
	}

	if len(valueSpec.Values) != 1 {
		panic("unexpected number of values")
	}

	value, ok := valueSpec.Values[0].(*ast.CompositeLit)
	if !ok {
		panic("unexpected type")
	}

	valueType, ok := value.Type.(*ast.Ident)
	if !ok {
		panic("unexpected type")
	}

	if valueType.Name != Locale {
		panic("unexpected struct")
	}

	v.locale = Object{
		Name:   valueType.Name,
		Fields: nil,
	}

	err := v.parseElements(&v.locale, "", value.Elts)
	if err != nil {
		fmt.Println("Err", err)
	}

	return v
}

func (p *localeValueVisitor) parseElementForLocaleKeySchoolType(objectFieldValueSchoolType *ObjectFieldValueSchoolType, element ast.Expr) error {
	typ, ok := element.(*ast.CompositeLit)
	if !ok {
		return errors.New("unexpected type, expecting *ast.CompositeLit")
	}

	if typ.Type.(*ast.Ident).Name != LocaleKeySchoolType {
		return errors.New("unexpected type, expecting LocaleKeySchoolType")
	}

	for _, elt := range typ.Elts {
		kv, ok := elt.(*ast.KeyValueExpr)
		if !ok {
			return errors.New("unexpected key value expression")
		}

		key, ok := kv.Key.(*ast.Ident)
		if !ok {
			return errors.New("unexpected key")
		}

		value, ok := kv.Value.(*ast.BasicLit)
		if !ok {
			return errors.New("unexpected value")
		}

		if value.Kind != token.STRING {
			return errors.New("unexpected value kind")
		}

		switch key.Name {
		case English:
			objectFieldValueSchoolType.English = getStringValueFromBasicLit(value)
		case Swedish:
			objectFieldValueSchoolType.Swedish = getStringValueFromBasicLit(value)
		default:
			return errors.New("unexpected key")
		}
	}

	return nil
}

func (p *localeValueVisitor) parseElementForLocaleKey(objFieldValue *ObjectFieldValue, elements []ast.Expr) error {
	for i := range elements {
		kv, ok := elements[i].(*ast.KeyValueExpr)
		if !ok {
			return errors.New("unexpected key value expression")
		}

		key, ok := kv.Key.(*ast.Ident)
		if !ok {
			return errors.New("unexpected key")
		}

		switch value := kv.Value.(type) {
		case *ast.BasicLit:
			if value.Kind != token.STRING {
				return errors.New("unexpected value kind")
			}

			switch key.Name {
			case English:
				objFieldValue.English = getStringValueFromBasicLit(value)
				objFieldValue.englishParams = getParamsFromString(objFieldValue.English)
			case Swedish:
				objFieldValue.Swedish = getStringValueFromBasicLit(value)
				objFieldValue.swedishParams = getParamsFromString(objFieldValue.Swedish)
			}

		case *ast.UnaryExpr: // IF POINTER (to LocaleKeySchoolType)
			var objFieldValueSchoolType ObjectFieldValueSchoolType

			err := p.parseElementForLocaleKeySchoolType(&objFieldValueSchoolType, value.X)
			if err != nil {
				return err
			}

			switch key.Name {
			case Preschool:
				objFieldValue.Preschool = &objFieldValueSchoolType
			case Elementary:
				objFieldValue.Elementary = &objFieldValueSchoolType
			case UpperSecondary:
				objFieldValue.UpperSecondary = &objFieldValueSchoolType
			default:
				return errors.New("unexpected key")
			}

		case *ast.Ident:
			if value.Obj != nil {
				return errors.New("unexpected type, expecting string or LocaleKeySchoolType")
			}

			switch key.Name {
			case Preschool, Elementary, UpperSecondary:
				// OK
			default:
				return errors.New("unexpected key Name")
			}

		default:
			return errors.New("unexpected type, expecting string or LocaleKeySchoolType")
		}
	}

	return nil
}

func (p *localeValueVisitor) findDefinition(name string) *Definition {
	for _, def := range p.definitions {
		if def.Name == name {
			return def
		}
	}

	return nil
}

func findTag(def *Definition, key string) string {
	for _, field := range def.Fields {
		if field.Name == key {
			tag := strings.TrimPrefix(field.Tag, "`json:\"")
			tag = strings.TrimSuffix(tag, "\"`")
			return tag
		}
	}

	return ""
}

func (p *localeValueVisitor) parseElements(obj *Object, tagPrefix string, elements []ast.Expr) error {
	def := p.findDefinition(obj.Name)

	for i := range elements {
		kv, ok := elements[i].(*ast.KeyValueExpr)
		if !ok {
			return errors.New("unexpected key value expression")
		}

		key, ok := kv.Key.(*ast.Ident)
		if !ok {
			return errors.New("unexpected key")
		}

		tag := findTag(def, key.Name)
		tagNested := tag

		if tagPrefix != "" {
			tagNested = tagPrefix + "." + tag
		}

		value, ok := kv.Value.(*ast.CompositeLit)
		if !ok {
			return errors.New("unexpected value")
		}

		valueType, ok := value.Type.(*ast.Ident)
		if !ok {
			return errors.New("unexpected type")
		}

		switch typeName := valueType.Name; typeName {
		case LocaleKey:
			var newObjFieldValue ObjectFieldValue

			err := p.parseElementForLocaleKey(&newObjFieldValue, value.Elts)
			if err != nil {
				return err
			}

			obj.Fields = append(obj.Fields, ObjectField{
				Position:         int(value.Pos()),
				Name:             key.Name,
				Tag:              tag,
				TagNested:        tagNested,
				Object:           nil,
				ObjectFieldValue: &newObjFieldValue,
			})

		default:
			newObj := Object{
				Name:   typeName,
				Fields: nil,
			}

			// Recursive but its fine the structs should already have been generated and validated to not have too nested structs
			err := p.parseElements(&newObj, tagNested, value.Elts)
			if err != nil {
				return err
			}

			obj.Fields = append(obj.Fields, ObjectField{
				Position:         int(value.Pos()),
				Name:             key.Name,
				Object:           &newObj,
				ObjectFieldValue: nil,
			})
		}
	}

	return nil
}

func getStringValueFromBasicLit(value *ast.BasicLit) string {
	stringValue := value.Value

	if stringValue == "" {
		stringValue = emptyString
	}

	return stringValue
}

func getParamsFromString(str string) []string {
	matches := extractParamsRegexp.FindAllStringSubmatch(str, -1)

	params := make([]string, len(matches))
	for i := range matches {
		params[i] = matches[i][1]
	}

	return params
}

// Params returns the "swedish"-params for the ObjectFieldValue,
// they should be validated to the same as the english params
func (p *ObjectFieldValue) Params() []string {
	return p.swedishParams
}
