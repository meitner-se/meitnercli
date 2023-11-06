type setupStruct struct {
   {{getServiceName }}Service *client.{{getServiceName | titleCase }}Service
}

func setup(t *testing.T) setupStruct {
	t.Helper()
	services := test_helpers.GetServicesAsSuperAdmin(t)

    return setupStruct{
       {{getServiceName }}Service:  services.{{getServiceName | titleCase }}Service,
    }
}
