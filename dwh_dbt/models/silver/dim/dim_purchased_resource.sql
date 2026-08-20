{{ config(materialized='table') }}

with name_map as (
    select * from {{ ref('int_purchase_name_map') }}
),

resource_source as (
    select distinct
        nullif(trim(pr."Mã"), '') as hg_stock_id
        , nullif(trim(pr."Tiêu đề"), '') as resources_name
        , coalesce(nm.canonical_name, trim(pr."Repository")) as partner_name
        , lower(coalesce(nm.canonical_name, trim(pr."Repository"))) as partner_key
    from {{ source('staging', 'purchased_resource') }} pr
    left join name_map nm
        on nm.alias_key = lower(
            regexp_replace(
                trim(pr."Repository")
                , '[[:space:]]+'
                , ' '
                , 'g'
            )
        )
    where trim(pr."Mã") ~ '^HGFA[0-9A-F]{32}$'
        and nullif(trim(pr."Repository"), '') is not null
),

partner_source_candidates as (
    select
        coalesce(nm_partner.canonical_name, nm_repo.canonical_name, trim(p."Tên đối tác")) as partner_name
        , nullif(trim(p."Ngày ký HĐ"), '') as buy_date
        , nullif(trim(p."Cách tính giá"), '') as repository_type
        , nullif(trim(p."Dự án"), '') as project_name
        , row_number() over (
            partition by coalesce(
                nm_partner.canonical_name
                , nm_repo.canonical_name
                , trim(p."Tên đối tác")
            )
            order by p._loaded_at desc nulls last
        ) as partner_order
    from {{ source('staging', 'partners') }} p
    left join name_map nm_partner
        on nm_partner.alias_key = lower(
            regexp_replace(trim(p."Tên đối tác"), '[[:space:]]+', ' ', 'g')
        )
    left join name_map nm_repo
        on nm_repo.alias_key = lower(
            regexp_replace(trim(p."Tên kho trên HG Stock"), '[[:space:]]+', ' ', 'g')
        )
    where nullif(trim(p."Tên đối tác"), '') is not null
),

partner_source as (
    select
        partner_name
        , buy_date
        , repository_type
        , project_name
    from partner_source_candidates
    where partner_order = 1
),

joined as (
    select
        r.hg_stock_id
        , r.resources_name
        , r.partner_name
        , r.partner_key
        , p.buy_date
        , p.repository_type
        , dsp.sub_project_id
        , dr.repository_id
        , row_number() over (
            partition by r.hg_stock_id, r.partner_key
            order by
                case
                    when dr.sub_project_id = dsp.sub_project_id then 1
                    else 2
                end
                , dr.repository_id
        ) as repository_order
    from resource_source r
    left join partner_source p
        on lower(p.partner_name) = r.partner_key
    left join {{ ref('dim_project') }} dp
        on p.project_name = dp.project_name
    left join {{ ref('dim_sub_project') }} dsp
        on dp.project_id = dsp.project_id
        and dsp.sub_project_name = 'Không có dự án con'
    left join {{ ref('dim_repository') }} dr
        on lower(
            regexp_replace(trim(dr.repository_name), '[[:space:]]+', ' ', 'g')
        ) = r.partner_key
        and (
            dsp.sub_project_id is null
            or dr.sub_project_id = dsp.sub_project_id
        )
)

select
    {{ dbt_utils.generate_surrogate_key([
        'hg_stock_id',
        'partner_key'
    ]) }} as dim_purchased_resource_sk
    , hg_stock_id
    , resources_name
    , repository_id as repository
    , partner_name
    , partner_key
    , {{ dbt_utils.generate_surrogate_key(['partner_key']) }} as partner_id
    , buy_date
    , repository_type
    , sub_project_id
from joined
where repository_order = 1

