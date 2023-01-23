# meitnercli

meitnercli is a wrapper for oto and sqlboiler.

## TODO
 - Get methods for unique combinations
 - Add text validations for colors, identity number etc.
 - Add size validation for VARCHAR
 - Add unique combination validation
 - Fix config lookup and use meitnercli.yml as default config
 - wipe specific service
 - stub specific layer
 - wipe specific layer
 - generate tests
 - caching in ORM layer 
    - Get-methods, try to get from cache, if not found, get from db and update cache
    - Create/Update-methods should update cache
 - non-join tables will be generated for upsert on Create and Update-methods, should not be possible
