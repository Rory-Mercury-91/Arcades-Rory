-- Ferme la création d'accès depuis l'application.
-- Le mot de passe vient du fichier .env du projet. Seul son empreinte est enregistrée ici.
-- À coller tel quel dans l'éditeur SQL.

create or replace function yams.keeper_ok(p_secret text)
returns boolean
language plpgsql
security definer
set search_path = yams, public, extensions
as $$
declare
  stored text;
begin
  if coalesce(btrim(p_secret), '') = '' then
    return false;
  end if;
  select secret_hash into stored from yams.keeper where id = 1;
  if stored is null then
    raise exception 'L''accès n''est pas encore en place.';
  end if;
  return encode(extensions.digest(convert_to(p_secret, 'UTF8'), 'sha256'), 'hex') = stored;
end;
$$;

create or replace function public.tables_admin_setup(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  return jsonb_build_object('ok', false, 'error', 'L''accès se règle dans le fichier .env du projet.');
end;
$$;

delete from yams.keeper;

-- @admin-hash
insert into yams.keeper (id, secret_hash)
values (1, 'efba8a6e962d646b893726b1021654f776bc51181edbbdadbab6de381b7317e7')
on conflict (id) do update set secret_hash = excluded.secret_hash;
-- @admin-hash-end

revoke all on function public.tables_admin_setup(text) from public, anon, authenticated;
revoke all on function yams.keeper_ok(text) from public, anon, authenticated;
