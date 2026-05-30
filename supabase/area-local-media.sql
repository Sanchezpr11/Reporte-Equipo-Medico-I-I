-- ============================================================================
--  FOTOS Y VIDEOS DE LA OFICINA — almacenamiento (Supabase Storage)
--  Crea el bucket privado 'office-media' y permisos por área:
--  solo usuarios con acceso al área (carpeta = area_key) pueden ver/subir/borrar.
--  El Storage ya viene activo en Supabase; esto solo crea el bucket + reglas.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

-- 1) Bucket privado, con límite de 50 MB por archivo
insert into storage.buckets (id, name, public, file_size_limit)
values ('office-media', 'office-media', false, 52428800)
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit;

-- 2) Permisos sobre los archivos (la 1ª carpeta de la ruta es el area_key)
drop policy if exists "office_media_select" on storage.objects;
create policy "office_media_select" on storage.objects for select to authenticated
    using (bucket_id = 'office-media' and public.has_area((storage.foldername(name))[1]));

drop policy if exists "office_media_insert" on storage.objects;
create policy "office_media_insert" on storage.objects for insert to authenticated
    with check (bucket_id = 'office-media' and public.has_area((storage.foldername(name))[1]));

drop policy if exists "office_media_delete" on storage.objects;
create policy "office_media_delete" on storage.objects for delete to authenticated
    using (bucket_id = 'office-media' and public.has_area((storage.foldername(name))[1]));
