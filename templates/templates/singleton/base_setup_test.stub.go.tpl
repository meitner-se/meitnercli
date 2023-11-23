type setupStruct struct {
   	organization        client.Organization
   	schoolOrganization  client.Organization
   	schoolTypeID        types.UUID
   	sas                 test_helpers.Services
   	superAdminServices  test_helpers.Services
   	superAdminID        types.UUID
   	schoolAdminServices test_helpers.Services
   	schoolAdminID       types.UUID
}

func setup(t *testing.T) setupStruct {
	t.Helper()

	services := test_helpers.NewServiceConstructor().AsSuperAdmin(t).Get()

	org, _ := test_helpers.CreateOrganization(t, services.OrganizationService)
	schoolOrganization, school, _ := test_helpers.CreateSchoolOrganization(t, services.OrganizationService, org, nil)
	admin, _ := test_helpers.AddAdminToSchool(t, schoolOrganization)
	adminServices := test_helpers.GetServicesByUserID(t, admin.ID, schoolOrganization.ID)

	return setupStruct{
		organization:        org,
		schoolOrganization:  schoolOrganization,
		schoolTypeID:        school.OrganizationSchoolTypeID,
		sas:                 test_helpers.GetServiceAccountServices(t, schoolOrganization),
		superAdminServices:  services,
		superAdminID:        services.Constructor.SuperAdmin.ID,
		schoolAdminServices: adminServices,
		schoolAdminID:       admin.ID,
	}
}
