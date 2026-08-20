with excluded_stock as (
    select hg_stock_id
    from {{ ref('int_excluded_stock_codes') }}
),

raw_repository_partner_map as (
    select *
    from (
        values
            ('Deep Disco', 'Deep Disco.xlsm')
            , ('Deep Disco', 'DEEP DISCO')
            , ('Deep Disco', 'Blink - BD - Deep House (Deep Disco)')
            , ('Das Ohr Digital', 'Chung (MKT3 cũ).xlsm')
            , ('Das Ohr Digital', 'TECH HOUSE')
            , ('Martynas Laurinavicius / Whitesand', 'Whitesand.xlsx')
            , ('Martynas Laurinavicius / Whitesand', 'Martynas Laurinavicius Whitesand')
            , ('Ardie Son', 'Aron Van Selm & Ardie Son')
            , ('PUEBLO VISTA POLYMESA KAI MOUSIKI LP', 'PVMM.xlsx')
            , ('PUEBLO VISTA POLYMESA KAI MOUSIKI LP', 'PVMM')
            , ('Selah Instrumental Music', 'Thu mua đối tác (Selah Instrumental Music).xlsm')
            , ('Selah Instrumental Music', 'Thu mua đối tác')
            , ('Breath Of Heaven', 'Thu mua đối tác (Breath Of Heaven).xlsx')
            , ('Breath Of Heaven', 'Thu mua đối tác')
            , ('Sergei Grishuk (Сергей Грищук)', 'Relax Nga - MKT1.xlsx')
            , ('Sergei Grishuk (Сергей Грищук)', 'Relax Nga - MKT1')
            , ('Sergei Grishuk (Сергей Грищук)', 'Sergei Grishuk (Сергей Грищук) Relax Nga')
            , ('Oleg Gorbonosov', 'Relax Nga - MKT1.xlsx')
            , ('Melnyk Ihor Olegovich', 'Relax Nga - MKT1.xlsx')
            , ('Tymur Khakimov', 'Relax Nga - MKT1.xlsx')
            , ('Palash Sunvaiya', 'Relax Nga - MKT1.xlsx')
            , ('Nikolay Statilko', 'Relax Nga - MKT1.xlsx')
            , ('Сергей Грищук (Sergey Grischuk)', 'Relax Nga - MKT1.xlsx')
            , ('Orangery', null)
            , ('Aron van Selm', 'Aron Van Selm & Ardie Son')
            , ('Sensoria', null)
            , ('Maniana', 'Maniana Records.xlsm')
            , ('Different Twins', 'Different Twins.xlsx')
            , ('Road Story Records', 'Road Story Records.xlsx')
            , ('Spectrum Recordings', 'Spectrum Recordings.xlsx')
            , ('Three Dot House', 'TECH HOUSE.xlsx')
            , ('Three Dot House', 'TECH HOUSE.xlsm')
            , ('Zero claim records', null)
            , ('Beyond music', 'Inside records.xlsx')
            , ('Beyond music', 'Inside Record')
            , ('Natural Deep (RA music)', 'Natural Deep (RA Music).xlsx')
            , ('Natural Deep (RA music)', 'Natural Deep (RA music)')
            , ('Day dose of house', 'Day Dose Of House.xlsm')
            , ('Deep strip', 'Deep Strip Records.xlsm')
            , ('Deep strip', 'Deep strip Record')
            , ('TFB', 'TFB records.xlsx')
            , ('TFB', 'TFB')
            , ('Wame record', null)
            , ('Lucid Plain', null)
            , ('Frequency', 'Frequency.xlsx')
            , ('Extra sound', 'Extra Sound.xlsx')
            , ('Extra sound', 'Extra Sound Record')
            , ('Tipsy', null)
            , ('Million records', 'Million Records.xlsx')
            , ('Mark Music Records', 'Mark Music Records.xlsm')
            , ('Pofiqist', 'Pofiqist.xlsx')
            , ('Lopills', null)
            , ('PVMM', 'PVMM.xlsx')
            , ('PVMM', 'PVMM')
            , ('Lofi Jazz Records', null)
            , ('Street Phonk'' Records', 'NHẠC DỪNG SỬ DỤNG.xlsx')
            , ('Street Phonk'' Records', 'NHẠC DỪNG SỬ DỤNG')
            , ('Aurorian '' Records', 'AURORIAN'' RECORD.xlsm')
            , ('Aurorian '' Records', 'AURORIAN'' RECORD')
            , ('HALIDON MUSIC', 'HalidonMusic.xlsx')
            , ('ALEX INSOURATSELOU', 'Thu mua nền tảng.xlsx')
    ) as mapping(partner_name, kho_name)
),

repository_partner_map as (
    select distinct partner_name, nullif(trim(kho_name), '') as kho_name
    from raw_repository_partner_map
    where nullif(trim(kho_name), '') is not null

    union

    select distinct
        partner_name
        , nullif(trim(regexp_replace(kho_name, '\.(xlsx|xlsm)$', '', 'i')), '') as kho_name
    from raw_repository_partner_map
    where nullif(trim(kho_name), '') is not null
),

-- A PO line can reference its Odoo song through x_song_id even when the song
-- itself does not persist purchase_order_line_id.
purchase_order_line_by_song as (
    select distinct on (x_song_id)
        x_song_id
        , nullif(trim(cast(id as text)), '') as po_detail_id
    from {{ source('staging', 'purchase_order_line') }}
    where x_song_id is not null
    order by
        x_song_id
        , write_date desc nulls last
        , id desc
),

odoo_resources as (
    select
        'odoo' as resource_source
        , nullif(trim(cast(id as text)), '') as source_resource_id
        , nullif(trim(cast(id as text)), '') as odoo_id
        , nullif(trim(cast(name as text)), '') as song_code
        , nullif(trim(cast(song_name as text)), '') as resource_name
        , nullif(trim(cast(subgenre_id as text)), '') as repository_id
        , 'Kho sản xuất' as repository_type
        , cast(nullif(trim(cast(review_score as text)), '') as numeric(18, 2)) as acceptance_score
        , cast(
            case
                when raw_acceptance_cost > 1000 then raw_acceptance_cost / 25000
                else raw_acceptance_cost
              end as numeric(18, 2)
          ) as acceptance_cost
        , cast(nullif(trim(cast(review_date as text)), '') as timestamp) as acceptance_date
        , nullif(trim(cast(detail_line_id as text)), '') as production_plan_detail_id
        , case
            when state = 'approved' and produce_state = 6 then 'Không nghiệm thu'
            when state = 'approved' and (produce_state <> 6 or produce_state is null) then 'Đã nghiệm thu'
            when state = 'draft' then 'Đang sản xuất'
            when state = 'rejected' then 'Không nghiệm thu'
            else null
          end as status
        , nullif(trim(cast(sale_order_id as text)), '') as so_id
        , coalesce(
            nullif(trim(cast(purchase_order_line_id as text)), '')
            , fallback_po_detail_id
          ) as po_detail_id
        , nullif(trim(cast(hg_code as text)), '') as hg_stock_id
    from (
        select
            xms.*
            , cast(nullif(trim(cast(review_price as text)), '') as numeric(18, 2)) as raw_acceptance_cost
            , pol.po_detail_id as fallback_po_detail_id
        from {{ source('staging', 'x_music_song') }} xms
        left join purchase_order_line_by_song pol on pol.x_song_id = xms.id
        where active = true
    ) odoo
),

purchased_base as (
    select distinct on (pr."Mã")
        'purchased' as resource_source
        , nullif(trim(pr."Mã"), '') as source_resource_id
        , cast(null as text) as odoo_id
        , cast(null as text) as song_code
        , nullif(trim(pr."Tiêu đề"), '') as resource_name
        , nullif(trim(cast(coalesce(
            dr_by_kho.repository_id, dr_direct.repository_id, dr_by_partner.repository_id
        ) as text)), '') as repository_id
        , nullif(trim(coalesce(
            p_direct."Cách tính giá", p_by_kho."Cách tính giá", p_by_partner."Cách tính giá"
        )), '') as repository_type
        , cast(null as numeric(18, 2)) as acceptance_score
        , cast(null as numeric(18, 2)) as acceptance_cost
        , cast(null as timestamp) as acceptance_date
        , cast(null as text) as production_plan_detail_id
        , 'Đã nghiệm thu' as status
        , cast(null as text) as so_id
        , cast(null as text) as po_detail_id
        , nullif(trim(pr."Mã"), '') as hg_stock_id
    from {{ source('staging', 'purchased_resource') }} pr
    left join repository_partner_map rpm_by_kho
        on lower(regexp_replace(normalize(nullif(trim(pr."Repository"), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(rpm_by_kho.kho_name), ''), nfc), '\s+', ' ', 'g'))
    left join repository_partner_map rpm_by_partner
        on lower(regexp_replace(normalize(nullif(trim(pr."Repository"), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(rpm_by_partner.partner_name), ''), nfc), '\s+', ' ', 'g'))
    left join {{ ref('dim_repository') }} dr_by_kho
        on lower(regexp_replace(normalize(nullif(trim(rpm_by_kho.partner_name), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(dr_by_kho.repository_name), ''), nfc), '\s+', ' ', 'g'))
    left join {{ ref('dim_repository') }} dr_direct
        on lower(regexp_replace(normalize(nullif(trim(pr."Repository"), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(dr_direct.repository_name), ''), nfc), '\s+', ' ', 'g'))
    left join {{ ref('dim_repository') }} dr_by_partner
        on lower(regexp_replace(normalize(nullif(trim(rpm_by_partner.kho_name), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(dr_by_partner.repository_name), ''), nfc), '\s+', ' ', 'g'))
    left join {{ source('staging', 'partners') }} p_direct
        on lower(regexp_replace(normalize(nullif(trim(pr."Repository"), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(p_direct."Tên kho trên HG Stock"), ''), nfc), '\s+', ' ', 'g'))
    left join {{ source('staging', 'partners') }} p_by_kho
        on lower(regexp_replace(normalize(nullif(trim(rpm_by_kho.partner_name), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(p_by_kho."Tên kho trên HG Stock"), ''), nfc), '\s+', ' ', 'g'))
    left join {{ source('staging', 'partners') }} p_by_partner
        on lower(regexp_replace(normalize(nullif(trim(rpm_by_partner.kho_name), ''), nfc), '\s+', ' ', 'g'))
            = lower(regexp_replace(normalize(nullif(trim(p_by_partner."Tên kho trên HG Stock"), ''), nfc), '\s+', ' ', 'g'))
    where trim(pr."Mã") ~ '^HGFA[A-F0-9]+$'
    order by
        pr."Mã"
        , coalesce(dr_by_kho.repository_id, dr_direct.repository_id, dr_by_partner.repository_id) nulls last
        , coalesce(rpm_by_kho.partner_name, pr."Repository", rpm_by_partner.kho_name) nulls last
),

-- RBO has project + sub-project but no warehouse column.  Resolve it in the
-- same hierarchy as performance and assign the default warehouse only.
canonical_projects_for_rbo as (
    select distinct on (
        lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'))
    )
        dp.project_id
        , lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g')) as project_name_key
    from {{ ref('dim_project') }} dp
    where dp.project_id is not null
        and nullif(trim(dp.project_name), '') is not null
    order by
        lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'))
        , case when dp.project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dp.project_id ~ '^[0-9]+$' then dp.project_id::numeric end nulls last
        , dp.project_id
),

canonical_sub_projects_for_rbo as (
    select distinct on (
        cp.project_id,
        lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g'))
    )
        cp.project_id
        , dsp.sub_project_id
        , lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g')) as sub_project_name_key
    from {{ ref('dim_sub_project') }} dsp
    inner join {{ ref('dim_project') }} raw_dp on raw_dp.project_id = dsp.project_id
    inner join canonical_projects_for_rbo cp
        on lower(regexp_replace(normalize(trim(raw_dp.project_name), nfc), '\s+', ' ', 'g')) = cp.project_name_key
    where dsp.sub_project_id is not null
        and nullif(trim(dsp.sub_project_name), '') is not null
    order by
        cp.project_id
        , lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g'))
        , case when dsp.project_id = cp.project_id then 0 else 1 end
        , case when dsp.sub_project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dsp.sub_project_id ~ '^[0-9]+$' then dsp.sub_project_id::numeric end nulls last
        , dsp.sub_project_id
),

canonical_repositories_for_rbo as (
    select distinct on (
        dr.sub_project_id,
        lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g'))
    )
        dr.repository_id
        , dr.sub_project_id
        , lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g')) as repository_name_key
    from {{ ref('dim_repository') }} dr
    where dr.repository_id is not null
        and dr.sub_project_id is not null
        and nullif(trim(dr.repository_name), '') is not null
    order by
        dr.sub_project_id
        , lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g'))
        , case when dr.repository_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dr.repository_id ~ '^[0-9]+$' then dr.repository_id::numeric end nulls last
        , dr.repository_id
),

before_odoo_base as (
    select
        rbo.*
        , cast(nullif(replace(trim(rbo."Chi phí đv: $"), ',', '.'), '') as numeric(18, 2)) as raw_acceptance_cost
        , cast(nullif(trim(rbo."Ngày nghiệm thu"), '') as timestamp) as parsed_acceptance_date
    from {{ source('staging', 'resource_before_odoo') }} rbo
),

before_odoo_resources as (
    select distinct on (trim(rbo."ISRC"))
        'before_odoo' as resource_source
        , nullif(trim(rbo."ISRC"), '') as source_resource_id
        , cast(null as text) as odoo_id
        , nullif(trim(rbo."Mã bài"), '') as song_code
        , nullif(trim(rbo."Tên bài gốc"), '') as resource_name
        -- RBO does not carry a warehouse. Use "Không có kho" of its resolved
        -- project/sub-project, never a same-named repository from another project.
        , nullif(trim(cast(dr_no_repo.repository_id as text)), '') as repository_id
        , 'Kho sản xuất' as repository_type
        , cast(nullif(trim(rbo."Điểm trung bình"), '') as numeric(18, 2)) as acceptance_score
        , cast(case when rbo.raw_acceptance_cost > 1000 then rbo.raw_acceptance_cost / 25000 else rbo.raw_acceptance_cost end as numeric(18, 2)) as acceptance_cost
        , rbo.parsed_acceptance_date as acceptance_date
        , cast(null as text) as production_plan_detail_id
        , nullif(trim(rbo."Tình trạng nghiệm thu"), '') as status
        , cast(null as text) as so_id
        , cast(null as text) as po_detail_id
        , nullif(trim(rbo."HG_Stock_ID"), '') as hg_stock_id
    from before_odoo_base rbo
    left join canonical_projects_for_rbo cp
        on lower(regexp_replace(normalize(trim(rbo."Thể loại"), nfc), '\s+', ' ', 'g')) = cp.project_name_key
    left join canonical_sub_projects_for_rbo csp
        on csp.project_id = cp.project_id
        and lower(regexp_replace(normalize(trim(rbo."Subgenre"), nfc), '\s+', ' ', 'g')) = csp.sub_project_name_key
    left join canonical_repositories_for_rbo dr_no_repo
        on dr_no_repo.sub_project_id = csp.sub_project_id
        and dr_no_repo.repository_name_key = lower(normalize('Không có kho', nfc))
    where nullif(trim(rbo."ISRC"), '') is not null
        and trim(rbo."ISRC") not in ('#N/A', '#REF!')
        and nullif(trim(rbo."HG_Stock_ID"), '') is not null
        and trim(rbo."HG_Stock_ID") <> 'Không tìm thấy'
        and rbo.parsed_acceptance_date <= timestamp '2025-08-31'
        and trim(rbo."Tình trạng nghiệm thu") like '%Đã nghiệm thu%'
    order by trim(rbo."ISRC")
),

performance_base as (
    select
        nullif(trim(rp."Mã Stock"), '') as hg_stock_id
        , coalesce(nullif(trim(rp."ISRC chốt"), ''), nullif(trim(rp."ISRC (Stock cũ)"), ''), nullif(trim(rp."ISRC (Stock mới)"), '')) as isrc
        , case when trim(rp."Mã BH") ~ '^[0-9]{4}_[A-Z0-9]+\([0-9]+_[A-Z]+_[A-Z]+\)_[A-Z]+_[0-9]+_[A-Z]+$' then trim(rp."Mã BH") else null end as song_code
        , nullif(trim(rp."Tên bài"), '') as resource_name
        , case
            when nullif(trim(rp."Kho (nếu có)"), '') is null or upper(trim(rp."Kho (nếu có)")) = '#N/A' then 'Không có kho'
            when lower(normalize(trim(rp."Kho (nếu có)"), nfc)) in ('audiojungle', 'nhạc nền audiojungle', 'nhạc nền tảng audiojungle', 'nền tảng audiojungle') then 'Audiojungle'
            else nullif(regexp_replace(normalize(trim(rp."Kho (nếu có)"), nfc), '\s+', ' ', 'g'), '')
          end as repository_name
        , nullif(regexp_replace(normalize(trim(rp."Dự án chốt"), nfc), '\s+', ' ', 'g'), '') as project_name
        , case
            when nullif(trim(rp."Dự án con (nếu có)"), '') is null
                or upper(trim(rp."Dự án con (nếu có)")) = '#N/A'
                or lower(normalize(trim(rp."Dự án con (nếu có)"), nfc)) = 'không có'
                then 'Không có dự án con'
            else nullif(regexp_replace(normalize(trim(rp."Dự án con (nếu có)"), nfc), '\s+', ' ', 'g'), '')
          end as sub_project_name
        , case when nullif(trim(rp."Điểm nghiệm thu"), '') ~ '^[0-9]+(\.[0-9]+)?$' then cast(trim(rp."Điểm nghiệm thu") as numeric(18, 2)) else cast(0 as numeric(18, 2)) end as acceptance_score
        , case
            when nullif(regexp_replace(trim(rp."Chi phí sx"), '[^0-9.]', '', 'g'), '') ~ '^[0-9]+(\.[0-9]+)?$'
                then cast(nullif(regexp_replace(trim(rp."Chi phí sx"), '[^0-9.]', '', 'g'), '') as numeric(18, 2))
            else null
          end as raw_acceptance_cost
        , cast(nullif(trim(rp."Ngày nghiệm thu"), '') as timestamp) as acceptance_date
    from {{ source('staging', 'resource_performance') }} rp
    where nullif(trim(rp."Mã Stock"), '') is not null
        and trim(rp."Mã Stock") ~ '^HGFA[A-F0-9]+$'
        and nullif(trim(rp."Dự án chốt"), '') is not null
        and upper(trim(rp."Dự án chốt")) <> '#N/A'
        and lower(normalize(trim(rp."Dự án chốt"), nfc)) <> 'không xác định'
),

canonical_projects as (
    select distinct on (
        lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'))
    )
        dp.project_id
        , lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g')) as project_name_key
    from {{ ref('dim_project') }} dp
    where dp.project_id is not null
        and nullif(trim(dp.project_name), '') is not null
    order by
        lower(regexp_replace(normalize(trim(dp.project_name), nfc), '\s+', ' ', 'g'))
        , case when dp.project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dp.project_id ~ '^[0-9]+$' then dp.project_id::numeric end nulls last
        , dp.project_id
),

canonical_sub_projects as (
    select distinct on (
        cp.project_id,
        lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g'))
    )
        cp.project_id
        , dsp.sub_project_id
        , lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g')) as sub_project_name_key
    from {{ ref('dim_sub_project') }} dsp
    inner join {{ ref('dim_project') }} raw_dp on raw_dp.project_id = dsp.project_id
    inner join canonical_projects cp
        on lower(regexp_replace(normalize(trim(raw_dp.project_name), nfc), '\s+', ' ', 'g')) = cp.project_name_key
    where dsp.sub_project_id is not null
        and nullif(trim(dsp.sub_project_name), '') is not null
    order by
        cp.project_id
        , lower(regexp_replace(normalize(trim(dsp.sub_project_name), nfc), '\s+', ' ', 'g'))
        , case when dsp.project_id = cp.project_id then 0 else 1 end
        , case when dsp.sub_project_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dsp.sub_project_id ~ '^[0-9]+$' then dsp.sub_project_id::numeric end nulls last
        , dsp.sub_project_id
),

canonical_repositories as (
    select distinct on (
        dr.sub_project_id,
        lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g'))
    )
        dr.repository_id
        , dr.sub_project_id
        , lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g')) as repository_name_key
    from {{ ref('dim_repository') }} dr
    where dr.repository_id is not null
        and dr.sub_project_id is not null
        and nullif(trim(dr.repository_name), '') is not null
    order by
        dr.sub_project_id
        , lower(regexp_replace(normalize(trim(dr.repository_name), nfc), '\s+', ' ', 'g'))
        , case when dr.repository_id ~ '^[0-9]+$' then 0 else 1 end
        , case when dr.repository_id ~ '^[0-9]+$' then dr.repository_id::numeric end nulls last
        , dr.repository_id
),

performance_resources as (
    select distinct on (pb.hg_stock_id)
        'performance' as resource_source
        , coalesce(pb.isrc, pb.hg_stock_id) as source_resource_id
        , cast(null as text) as odoo_id
        , pb.song_code
        , pb.resource_name
        , coalesce(dr_requested.repository_id, dr_no_repo.repository_id) as repository_id
        , cast(null as text) as repository_type
        , pb.acceptance_score
        , cast(
            case
                when pb.raw_acceptance_cost > 1000000 then pb.raw_acceptance_cost / 25000
                when pb.raw_acceptance_cost is not null then pb.raw_acceptance_cost
                else null
              end as numeric(18, 2)
          ) as acceptance_cost
        , pb.acceptance_date
        , cast(null as text) as production_plan_detail_id
        , cast(null as text) as status
        , cast(null as text) as so_id
        , cast(null as text) as po_detail_id
        , pb.hg_stock_id
    from performance_base pb
    inner join canonical_projects cp
        on lower(regexp_replace(normalize(trim(pb.project_name), nfc), '\s+', ' ', 'g')) = cp.project_name_key
    inner join canonical_sub_projects csp
        on csp.project_id = cp.project_id
        and lower(regexp_replace(normalize(trim(pb.sub_project_name), nfc), '\s+', ' ', 'g')) = csp.sub_project_name_key
    left join canonical_repositories dr_requested
        on dr_requested.sub_project_id = csp.sub_project_id
        and dr_requested.repository_name_key
            = lower(regexp_replace(normalize(trim(pb.repository_name), nfc), '\s+', ' ', 'g'))
    left join canonical_repositories dr_no_repo
        on dr_no_repo.sub_project_id = csp.sub_project_id
        and dr_no_repo.repository_name_key = lower(normalize('Không có kho', nfc))
    order by
        pb.hg_stock_id
        , (dr_requested.repository_id is not null) desc
        , (pb.song_code is not null) desc
        , (pb.acceptance_date is not null) desc
        , pb.acceptance_date desc nulls last
),

base_union as (
    select * from odoo_resources
    union all
    select * from purchased_base
    union all
    select * from before_odoo_resources
),

existing_resources_enriched as (
    select
        b.resource_source
        , b.source_resource_id
        , b.odoo_id
        , coalesce(b.song_code, p.song_code) as song_code
        , coalesce(b.resource_name, p.resource_name) as resource_name
        -- For a stock with a valid final project, the performance mapping is
        -- authoritative because it is scoped to project and sub-project.
        , coalesce(p.repository_id, b.repository_id) as repository_id
        , b.repository_type
        , coalesce(b.acceptance_score, p.acceptance_score) as acceptance_score
        , coalesce(b.acceptance_cost, p.acceptance_cost) as acceptance_cost
        , coalesce(b.acceptance_date, p.acceptance_date) as acceptance_date
        , b.production_plan_detail_id
        , b.status
        , b.so_id
        , b.po_detail_id
        , b.hg_stock_id
    from base_union b
    left join performance_resources p on p.hg_stock_id = b.hg_stock_id
),

performance_only_resources as (
    select
        p.resource_source
        , p.source_resource_id
        , p.odoo_id
        , p.song_code
        , p.resource_name
        , p.repository_id
        , p.repository_type
        , p.acceptance_score
        , p.acceptance_cost
        , p.acceptance_date
        , p.production_plan_detail_id
        , p.status
        , p.so_id
        , p.po_detail_id
        , p.hg_stock_id
    from performance_resources p
    where not exists (
        select 1
        from base_union b
        where b.hg_stock_id = p.hg_stock_id
    )
),

unioned as (
    select * from existing_resources_enriched
    union all
    select * from performance_only_resources
),

filtered_unioned as (
    select u.*
    from unioned u
    where u.hg_stock_id is null
       or not exists (
            select 1
            from excluded_stock e
            where e.hg_stock_id = upper(trim(u.hg_stock_id))
       )
)

select
    {{ dbt_utils.generate_surrogate_key(['resource_source', 'source_resource_id']) }} as dim_resources_sk
    , resource_source
    , odoo_id
    , song_code
    , resource_name
    , repository_id
    , repository_type
    , acceptance_score
    , acceptance_cost
    , acceptance_date
    , production_plan_detail_id
    , status
    , so_id
    , po_detail_id
    , hg_stock_id
from filtered_unioned