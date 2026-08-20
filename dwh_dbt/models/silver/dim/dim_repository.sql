-- Replacement model for dim_repository.
-- Repository names are stored as NFC, trimmed and with repeated whitespace collapsed.
-- When duplicate names exist under one canonical sub-project, numeric IDs are retained.

with canonical_projects as (
    select
        dp.project_id as canonical_project_id
        , nullif(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'), '') as project_name
    from {{ ref('dim_project') }} dp
    where dp.project_id is not null
        and nullif(trim(dp.project_name), '') is not null
),

canonical_sub_projects as (
    select distinct on (
        dsp.project_id,
        lower(normalize(trim(dsp.sub_project_name), nfc))
    )
        dsp.sub_project_id as source_sub_project_id
        , dsp.sub_project_id as canonical_sub_project_id
        , dsp.project_id as canonical_project_id
        , nullif(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g'), '') as sub_project_name
    from {{ ref('dim_sub_project') }} dsp
    where dsp.sub_project_id is not null
        and dsp.project_id is not null
        and nullif(trim(dsp.sub_project_name), '') is not null
    order by
        dsp.project_id
        , lower(normalize(trim(dsp.sub_project_name), nfc))
        , case when dsp.sub_project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dsp.sub_project_id ~ '^[0-9]+$' then dsp.sub_project_id::numeric end nulls last
        , dsp.sub_project_id
),

from_odoo as (
    select
        nullif(trim(cast(xps.id as text)), '') as repository_id
        , coalesce(
            csp.canonical_sub_project_id,
            nullif(trim(cast(xps.product_genre_id as text)), '')
        ) as sub_project_id
        , nullif(regexp_replace(normalize(trim(cast(xps.name as text)), nfc), '\s+', ' ', 'g'), '') as repository_name
        , 1 as source_priority
    from {{ source('staging', 'x_product_subgenre') }} xps
    left join canonical_sub_projects csp
        on nullif(trim(cast(xps.product_genre_id as text)), '')
            = csp.source_sub_project_id
    where nullif(trim(cast(xps.product_genre_id as text)), '') is not null
        and xps.order_type = 'music'
),

from_partners as (
    select
        {{ dbt_utils.generate_surrogate_key([
            'p."Tên đối tác"',
            'cast(csp.canonical_sub_project_id as text)'
        ]) }} as repository_id
        , cast(csp.canonical_sub_project_id as text) as sub_project_id
        , nullif(regexp_replace(normalize(trim(p."Tên đối tác"), nfc), '\s+', ' ', 'g'), '') as repository_name
        , 2 as source_priority
    from {{ source('staging', 'partners') }} p
    inner join canonical_projects cp
        on lower(normalize(trim(p."Dự án"), nfc))
            = lower(normalize(cp.project_name, nfc))
    inner join canonical_sub_projects csp
        on csp.canonical_project_id = cp.canonical_project_id
        and lower(normalize(csp.sub_project_name, nfc))
            = lower(normalize('Không có dự án con', nfc))
    where nullif(trim(p."Tên đối tác"), '') is not null
        and not exists (
            select 1
            from from_odoo fo
            where fo.sub_project_id = cast(csp.canonical_sub_project_id as text)
                and lower(normalize(fo.repository_name, nfc))
                    = lower(normalize(trim(p."Tên đối tác"), nfc))
        )
),

performance_clean as (
    select distinct
        case
            when nullif(trim(p."Kho (nếu có)"), '') is null
                or upper(trim(p."Kho (nếu có)")) = '#N/A'
                then 'Không có kho'
            when lower(normalize(trim(p."Kho (nếu có)"), nfc)) in (
                'audiojungle',
                'nhạc nền audiojungle',
                'nhạc nền tảng audiojungle',
                'nền tảng audiojungle'
            ) then 'Audiojungle'
            else nullif(regexp_replace(normalize(trim(p."Kho (nếu có)"), nfc), '\s+', ' ', 'g'), '')
          end as repository_name
        , nullif(regexp_replace(normalize(trim(p."Dự án chốt"), nfc), '\s+', ' ', 'g'), '') as project_name
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

from_performance as (
    select
        {{ dbt_utils.generate_surrogate_key([
            'pc.repository_name',
            'cast(csp.canonical_sub_project_id as text)'
        ]) }} as repository_id
        , cast(csp.canonical_sub_project_id as text) as sub_project_id
        , pc.repository_name
        , 3 as source_priority
    from performance_clean pc
    inner join canonical_projects cp
        on lower(normalize(pc.project_name, nfc))
            = lower(normalize(cp.project_name, nfc))
    inner join canonical_sub_projects csp
        on csp.canonical_project_id = cp.canonical_project_id
        and lower(normalize(pc.sub_project_name, nfc))
            = lower(normalize(csp.sub_project_name, nfc))
    where not exists (
        select 1
        from from_odoo fo
        where fo.sub_project_id = cast(csp.canonical_sub_project_id as text)
            and lower(normalize(fo.repository_name, nfc))
                = lower(normalize(pc.repository_name, nfc))
    )
),

combined as (
    select * from from_odoo
    union all
    select * from from_partners
    union all
    select * from from_performance
),

normalised_combined as (
    select
        repository_id
        , sub_project_id
        , nullif(regexp_replace(normalize(trim(repository_name), nfc), '\s+', ' ', 'g'), '') as repository_name
        , source_priority
    from combined
    where repository_id is not null
        and sub_project_id is not null
        and nullif(trim(repository_name), '') is not null
),

deduped as (
    select distinct on (
        sub_project_id,
        lower(normalize(repository_name, nfc))
    )
        repository_id
        , sub_project_id
        , repository_name
    from normalised_combined
    order by
        sub_project_id
        , lower(normalize(repository_name, nfc))
        , case when repository_id ~ '^[0-9]+$' then 0 else 1 end
        , case when repository_id ~ '^[0-9]+$' then repository_id::numeric end nulls last
        , source_priority
        , repository_id
),

default_per_sub_project as (
    select
        {{ dbt_utils.generate_surrogate_key([
            'cast(csp.canonical_sub_project_id as text)',
            "'Không có kho'"
        ]) }} as repository_id
        , cast(csp.canonical_sub_project_id as text) as sub_project_id
        , 'Không có kho' as repository_name
    from canonical_sub_projects csp
    where not exists (
        select 1
        from deduped d
        where d.sub_project_id = cast(csp.canonical_sub_project_id as text)
            and lower(normalize(d.repository_name, nfc))
                = lower(normalize('Không có kho', nfc))
    )
),

with_default as (
    select * from deduped
    union all
    select * from default_per_sub_project
)

select distinct on (repository_id)
    {{ dbt_utils.generate_surrogate_key(['repository_id']) }} as dim_repository_sk
    , repository_id
    , sub_project_id
    , repository_name
from with_default
order by repository_id, sub_project_id, repository_name
