-- Shared exclusion set used by every downstream model.
-- Rule 1: all stock codes currently located in FOREST MUSIC GROUP or descendants.
-- Rule 2: historical codes from the supplied removal list that no longer map to that tree.
{{ config(materialized='table') }}

with recursive forest_music_folders as (
    select f."Id"
    from {{ source('staging', 'resource_folders') }} f
    where f."Id" = '9bfa70be-e51a-4513-b08f-5c38e755b7f3'

    union

    select child."Id"
    from {{ source('staging', 'resource_folders') }} child
    join forest_music_folders parent
        on child."ParentNodeId" = parent."Id"
),

forest_music_stock as (
    select distinct
        upper(trim(cast(rfi."ResourceFileId" as text))) as hg_stock_id
    from {{ source('staging', 'resource_file_info') }} rfi
    join forest_music_folders ff
        on rfi."ResourceFolderId" = ff."Id"
    where nullif(trim(cast(rfi."ResourceFileId" as text)), '') is not null
),

manual_excluded as (
    select distinct
        upper(trim(cast(hg_stock_id as text))) as hg_stock_id
    from {{ ref('manual_excluded_stock_codes') }}
    where nullif(trim(cast(hg_stock_id as text)), '') is not null
)

select hg_stock_id from forest_music_stock
union
select hg_stock_id from manual_excluded
