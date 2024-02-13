update ENTITY set entityparent={2} where entityparent={1} and entitytype=3
update METADATA set metadataval={2} where metadatakey=24 and entityparent={1} and entity in (select entity from ENTITY where entitytype=3)
