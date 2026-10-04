-- TEST ONLY: minimal Storage relations for local PostgreSQL.
-- Hosted projects already have this schema. Never apply this file to a
-- Supabase project. It refuses every database except eldafttar_notes_test.
-- Apply it before 20261004090000_daily_notes_and_ledger_pagination.sql.
do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() is distinct from 'eldafttar_notes_test' then
    raise exception 'refusing storage bootstrap outside local eldafttar_notes_test';
  end if;
end;
$guard$;

create schema if not exists storage;

do $storage_bootstrap$
begin
  if to_regclass('storage.buckets') is null then
    execute $ddl$
      create table storage.buckets (
        id text primary key,
        name text not null,
        "public" boolean not null default false,
        file_size_limit bigint,
        allowed_mime_types text[],
        created_at timestamptz not null default pg_catalog.now(),
        updated_at timestamptz not null default pg_catalog.now()
      )
    $ddl$;
  end if;
  if to_regclass('storage.objects') is null then
    execute $ddl$
      create table storage.objects (
        id uuid primary key default gen_random_uuid(),
        bucket_id text not null references storage.buckets (id),
        name text not null,
        owner uuid,
        owner_id text,
        metadata jsonb,
        created_at timestamptz not null default pg_catalog.now(),
        updated_at timestamptz not null default pg_catalog.now(),
        unique (bucket_id, name)
      )
    $ddl$;
  end if;
  if to_regprocedure('storage.foldername(text)') is null then
    execute $ddl$
      create function storage.foldername(name text)
      returns text[]
      language plpgsql
      immutable
      as $body$
      declare
        parts text[];
      begin
        parts := string_to_array(name, '/');
        return parts[1 : coalesce(array_length(parts, 1), 0) - 1];
      end;
      $body$
    $ddl$;
  end if;
  if to_regprocedure('storage.filename(text)') is null then
    execute $ddl$
      create function storage.filename(name text)
      returns text
      language sql
      immutable
      as $body$
        select (string_to_array(name, '/'))[
          coalesce(array_length(string_to_array(name, '/'), 1), 1)
        ];
      $body$
    $ddl$;
  end if;
  if to_regprocedure('storage.extension(text)') is null then
    execute $ddl$
      create function storage.extension(name text)
      returns text
      language sql
      immutable
      as $body$
        select reverse(split_part(reverse(storage.filename(name)), '.', 1));
      $body$
    $ddl$;
  end if;
end;
$storage_bootstrap$;
