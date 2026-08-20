-- Replacement model for dim_project.
-- RBO is a first-class project source; it no longer depends on dim_sub_project.

with from_odoo as (
    select
        nullif(trim(cast(id as text)), '') as project_id
        , nullif(regexp_replace(normalize(trim(cast(name as text)), nfc), '\s+', ' ', 'g'), '') as project_name
        , nullif(trim(cast(state as text)), '') as status
    from {{ source('staging', 'x_project') }}
),

from_partners as (
    select
        {{ dbt_utils.generate_surrogate_key(['"Dự án"']) }} as project_id
        , nullif(regexp_replace(normalize(trim("Dự án"), nfc), '\s+', ' ', 'g'), '') as project_name
        , cast(null as text) as status
    from {{ source('staging', 'partners') }}
    where nullif(trim("Dự án"), '') is not null
),

rbo_project_names as (
    select distinct on (project_name_key)
        project_name
        , project_name_key
    from (
        select
            nullif(regexp_replace(normalize(trim(rbo."Thể loại"), nfc), '\s+', ' ', 'g'), '') as project_name
            , lower(regexp_replace(normalize(trim(rbo."Thể loại"), nfc), '\s+', ' ', 'g')) as project_name_key
        from {{ source('staging', 'resource_before_odoo') }} rbo
        where nullif(trim(rbo."Thể loại"), '') is not null
    ) rbo
    where project_name is not null
    order by project_name_key, project_name
),

from_resource_before_odoo as (
    select
        {{ dbt_utils.generate_surrogate_key(['project_name_key']) }} as project_id
        , project_name
        , cast(null as text) as status
    from rbo_project_names
),

performance_projects as (
    select distinct on (project_name_key)
        project_name
        , project_name_key
    from (
        select
            nullif(regexp_replace(normalize(trim(p."Dự án chốt"), nfc), '\s+', ' ', 'g'), '') as project_name
            , lower(regexp_replace(normalize(trim(p."Dự án chốt"), nfc), '\s+', ' ', 'g')) as project_name_key
        from {{ source('staging', 'resource_performance') }} p
        where nullif(trim(p."Dự án chốt"), '') is not null
            and upper(trim(p."Dự án chốt")) <> '#N/A'
            and lower(normalize(trim(p."Dự án chốt"), nfc)) <> 'không xác định'
    ) performance
    where project_name is not null
    order by project_name_key, project_name
),

from_performance as (
    select
        {{ dbt_utils.generate_surrogate_key(['project_name_key']) }} as project_id
        , project_name
        , cast(null as text) as status
    from performance_projects
),

combined as (
    select * from from_odoo
    union all
    select * from from_partners
    union all
    select * from from_resource_before_odoo
    union all
    select * from from_performance
),

normalised_combined as (
    select
        project_id
        , nullif(regexp_replace(normalize(trim(project_name), nfc), '\s+', ' ', 'g'), '') as project_name
        , status
        , lower(regexp_replace(normalize(trim(project_name), nfc), '\s+', ' ', 'g')) as project_name_key
    from combined
    where project_id is not null
        and nullif(trim(project_name), '') is not null
),

canonical_by_name as (
    select distinct on (project_name_key)
        project_id
        , project_name
        , status
    from normalised_combined
    order by
        project_name_key
        , case when project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when project_id ~ '^[0-9]+$' then project_id::numeric end nulls last
        , project_id
        , project_name
        , status nulls last
),

canonical_by_id as (
    select distinct on (project_id)
        project_id
        , project_name
        , status
    from canonical_by_name
    order by project_id, project_name, status nulls last
)

select
    {{ dbt_utils.generate_surrogate_key(['project_id']) }} as dim_project_sk
    , project_id
    , project_name
    , status
from canonical_by_id
