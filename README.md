# meitnercli

meitnercli is a wrapper for oto and sqlboiler.

## TODO
 - Get methods for unique combinations
 - Add text validations for colors, identity number etc.
 - Add size validation for VARCHAR
 - Add unique combination validation
 - generate tests
 - caching in ORM layer 
    - Get-methods, try to get from cache, if not found, get from db and update cache
    - Create/Update-methods should update cache
