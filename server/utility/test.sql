select * from METADATA where entity={1}
select * from METADATA natural left join METADATAKEY where entity={1}
