-- Replacement model for dim_sub_project.
-- project_id_overrides is retained for the existing 129 -> 163 business mapping.
-- Duplicate names under one canonical project keep a numeric sub_project_id first.

with project_id_overrides as (
    select '129'::text as legacy_project_id, '163'::text as canonical_project_id
),

canonical_project_aliases as (
    select distinct on (source_project_id)
        source_project_id
        , canonical_project_id
    from (
        -- Preserve every Odoo ID as an alias, but point it at the
        -- canonical ID selected by dim_project for the same normalised name.
        select
            nullif(trim(cast(xp.id as text)), '') as source_project_id
            , coalesce(o.canonical_project_id, dp.project_id) as canonical_project_id
        from {{ source('staging', 'x_project') }} xp
        inner join {{ ref('dim_project') }} dp
            on lower(regexp_replace(normalize(trim(xp.name), nfc), '\s+', ' ', 'g'))
                = lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'))
        left join project_id_overrides o
            on nullif(trim(cast(xp.id as text)), '') = o.legacy_project_id

        union all

        select
            dp.project_id as source_project_id
            , coalesce(o.canonical_project_id, dp.project_id) as canonical_project_id
        from {{ ref('dim_project') }} dp
        left join project_id_overrides o
            on dp.project_id = o.legacy_project_id
    ) aliases
    where source_project_id is not null
        and canonical_project_id is not null
    order by
        source_project_id
        , case when canonical_project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when canonical_project_id ~ '^[0-9]+$'
            then canonical_project_id::numeric end nulls last
        , canonical_project_id
),

from_odoo as (
    select
        nullif(trim(cast(xpg.id as text)), '') as sub_project_id
        , coalesce(
            o.canonical_project_id,
            pa.canonical_project_id,
            nullif(trim(cast(xpg.project_id as text)), ''),
            (
                select nullif(trim(cast(xp.id as text)), '')
                from {{ source('staging', 'x_project') }} xp
                where lower(normalize(trim(xp.name), nfc))
                    = lower(normalize(trim(xpg.name), nfc))
                order by xp.id
                limit 1
            )
        ) as project_id
        , coalesce(
            nullif(regexp_replace(normalize(trim(cast(xpg.name as text)), nfc), '\s+', ' ', 'g'), ''),
            'Không có dự án con'
        ) as sub_project_name
        , nullif(trim(cast(xpg.description as text)), '') as description
        , 1 as source_priority
    from {{ source('staging', 'x_product_genre') }} xpg
    left join project_id_overrides o
        on nullif(trim(cast(xpg.project_id as text)), '') = o.legacy_project_id
    left join canonical_project_aliases pa
        on nullif(trim(cast(xpg.project_id as text)), '') = pa.source_project_id
    where xpg.order_type = 'music'
),

resource_before_odoo_resolved_raw as (
    select
        coalesce(
            (
                select dp.project_id
                from {{ ref('dim_project') }} dp
                where lower(normalize(trim(dp.project_name), nfc))
                    = lower(normalize(trim(rbo."Thể loại"), nfc))
                order by
                    case when dp.project_id ~ '^[0-9]+$' then 0 else 1 end,
                    case when dp.project_id ~ '^[0-9]+$' then dp.project_id::numeric end nulls last,
                    dp.project_id
                limit 1
            ),
            (
                select pa.canonical_project_id
                from {{ source('staging', 'x_project') }} xp
                inner join canonical_project_aliases pa
                    on pa.source_project_id = nullif(trim(cast(xp.id as text)), '')
                where lower(regexp_replace(normalize(trim(xp.name), nfc), '\s+', ' ', 'g'))
                    = lower(regexp_replace(normalize(trim(rbo."Thể loại"), nfc), '\s+', ' ', 'g'))
                order by
                    case when pa.canonical_project_id ~ '^[0-9]+$' then 0 else 1 end,
                    case when pa.canonical_project_id ~ '^[0-9]+$'
                        then pa.canonical_project_id::numeric end nulls last,
                    pa.canonical_project_id
                limit 1
            ),
            -- Must use the same canonical key as dim_project_rbo_complete.
            {{ dbt_utils.generate_surrogate_key([
                "lower(regexp_replace(normalize(trim(rbo.\"Thể loại\"), nfc), '\\s+', ' ', 'g'))"
            ]) }}
        ) as project_id
        , coalesce(
            nullif(regexp_replace(normalize(trim(rbo."Subgenre"), nfc), '\s+', ' ', 'g'), ''),
            'Không có dự án con'
        ) as sub_project_name
    from {{ source('staging', 'resource_before_odoo') }} rbo
    where nullif(trim(rbo."Subgenre"), '') is not null
),

resource_before_odoo_resolved as (
    select
        coalesce(o.canonical_project_id, r.project_id) as project_id
        , r.sub_project_name
    from resource_before_odoo_resolved_raw r
    left join project_id_overrides o on r.project_id = o.legacy_project_id
),

from_resource_before_odoo as (
    select
        {{ dbt_utils.generate_surrogate_key(['project_id', 'sub_project_name']) }} as sub_project_id
        , project_id
        , sub_project_name
        , cast(null as text) as description
        , 2 as source_priority
    from resource_before_odoo_resolved
    where project_id is not null
),

performance_clean as (
    select distinct
        nullif(regexp_replace(normalize(trim(p."Dự án chốt"), nfc), '\s+', ' ', 'g'), '') as project_name
        , case
            when nullif(trim(p."Dự án con (nếu có)"), '') is null
                or upper(trim(p."Dự án con (nếu có)")) = '#N/A'
                or lower(normalize(trim(p."Dự án con (nếu có)"), nfc)) = 'không có'
                then 'Không có dự án con'
            else nullif(regexp_replace(normalize(trim(p."Dự án con (nếu có)"), nfc), '\s+', ' ', 'g'), '')
          end as sub_project_name
    from {{ source('staging', 'resource_performance') }} p
    where nullif(trim(p."Dự án chốt"), '') is not null
        and upper(trim(p."Dự án chốt")) <> '#N/A'
        and lower(normalize(trim(p."Dự án chốt"), nfc)) <> 'không xác định'
),

performance_resolved as (
    select distinct
        coalesce(o.canonical_project_id, dp.project_id) as project_id
        , pc.sub_project_name
    from performance_clean pc
    inner join {{ ref('dim_project') }} dp
        on lower(normalize(pc.project_name, nfc))
            = lower(normalize(dp.project_name, nfc))
    left join project_id_overrides o on dp.project_id = o.legacy_project_id
),

from_performance as (
    select
        {{ dbt_utils.generate_surrogate_key(['pr.project_id', 'pr.sub_project_name']) }} as sub_project_id
        , pr.project_id
        , pr.sub_project_name
        , cast(null as text) as description
        , 3 as source_priority
    from performance_resolved pr
    where not exists (
        select 1
        from from_odoo fo
        where fo.project_id = pr.project_id
            and lower(normalize(fo.sub_project_name, nfc))
                = lower(normalize(pr.sub_project_name, nfc))
    )
),

combined as (
    select * from from_odoo
    union all
    select * from from_resource_before_odoo
    union all
    select * from from_performance
),

canonical_combined as (
    select
        c.sub_project_id
        , coalesce(o.canonical_project_id, c.project_id) as project_id
        , nullif(regexp_replace(normalize(trim(c.sub_project_name), nfc), '\s+', ' ', 'g'), '') as sub_project_name
        , c.description
        , c.source_priority
    from combined c
    left join project_id_overrides o on c.project_id = o.legacy_project_id
    where c.sub_project_id is not null
        and c.project_id is not null
        and nullif(trim(c.sub_project_name), '') is not null
),

deduped as (
    select distinct on (
        project_id,
        lower(normalize(sub_project_name, nfc))
    )
        sub_project_id
        , project_id
        , sub_project_name
        , description
    from canonical_combined
    order by
        project_id
        , lower(normalize(sub_project_name, nfc))
        , case when sub_project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when sub_project_id ~ '^[0-9]+$' then sub_project_id::numeric end nulls last
        , source_priority
        , sub_project_id
),

canonical_projects as (
    select distinct coalesce(o.canonical_project_id, dp.project_id) as project_id
    from {{ ref('dim_project') }} dp
    left join project_id_overrides o on dp.project_id = o.legacy_project_id
),

default_per_project as (
    select
        {{ dbt_utils.generate_surrogate_key(['cp.project_id', "'Không có dự án con'"]) }} as sub_project_id
        , cp.project_id
        , 'Không có dự án con' as sub_project_name
        , cast(null as text) as description
    from canonical_projects cp
    where not exists (
        select 1
        from deduped d
        where d.project_id = cp.project_id
            and lower(normalize(d.sub_project_name, nfc))
                = lower(normalize('Không có dự án con', nfc))
    )
),

with_default as (
    select * from deduped
    union all
    select * from default_per_project
)

select distinct on (sub_project_id)
    {{ dbt_utils.generate_surrogate_key(['sub_project_id']) }} as dim_sub_project_sk
    , sub_project_id
    , project_id
    , sub_project_name
    , description
from with_default
order by sub_project_id, project_id, sub_project_name
