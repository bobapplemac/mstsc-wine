SECTIONS
{
  . = SIZEOF_HEADERS;
  . = ALIGN(__section_alignment__);
  .rsrc __image_base__ + ( __section_alignment__ < 0x1000 ? . : __section_alignment__ ) : { *(.rsrc) *(.rsrc$*) }
  /DISCARD/ : { *(*) }
}
