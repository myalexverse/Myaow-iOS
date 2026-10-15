-- Contact lookup is case-insensitive; ownership uses the same uniqueness rule.
create unique index profiles_id_casefold_unique on myaow_private.profiles(lower(id));
drop index myaow_private.profiles_id_casefold;
