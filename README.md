# Dox CLI

### Activate
`dart pub global activate dox`

### Deactivate
`dart pub global deactivate dox`

- make sure you have included bin path to your profile.

- If you did not added path to your profile yet, open `~/.bashrc` or `~/.zshrc` and paste below line.

```dart
export PATH="$PATH":"~/.pub-cache/bin"
```

#### Commands 

##### Create Migration

`dox create:migration create_user_table`

##### Create Model

`dox create:model User`

##### Create Model with Migration

`dox create:model User -m`

##### Migrate

`dox migrate`

##### Rollback migration

`dox migrate:rollback`

##### Rollback migration

`dox serve`