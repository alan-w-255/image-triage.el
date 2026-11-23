/* jpgpreview -- write an embedded thumbnail or preview of a JPEG to stdout.

   Usage: jpgpreview thumb|preview FILE

   thumb    the small Exif thumbnail (IFD1, typically 160x120)
   preview  the large MPF preview ("Large Thumbnail", VGA or full HD)

   Exit status: 0 = written to stdout, 1 = not present, 2 = error/usage.

   Build: cc -O2 -Wall -o jpgpreview jpgpreview.c

   This file was written by Claude Fable 5.2.  */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>

static int le;			/* byte order of the current TIFF block */

static uint32_t
g16 (const unsigned char *p)
{
  return le ? (uint32_t) p[0] | p[1] << 8 : (uint32_t) p[0] << 8 | p[1];
}

static uint32_t
g32 (const unsigned char *p)
{
  return le
    ? (uint32_t) p[0] | p[1] << 8 | p[2] << 16 | (uint32_t) p[3] << 24
    : (uint32_t) p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
}

/* Check TIFF header at T (N bytes long) and set byte order.  */
static int
tiff_header (const unsigned char *t, size_t n)
{
  if (n < 8)
    return 0;
  if (t[0] == 'I' && t[1] == 'I')
    le = 1;
  else if (t[0] == 'M' && t[1] == 'M')
    le = 0;
  else
    return 0;
  return 1;
}

/* Find the IFD1 JPEG thumbnail in an Exif TIFF block.  Offsets are
   relative to T.  */
static int
find_exif_thumb (const unsigned char *t, size_t n, size_t *off, size_t *len)
{
  uint32_t ifd0, cnt, next, ifd1, i, o = 0, l = 0;

  if (!tiff_header (t, n))
    return 0;
  ifd0 = g32 (t + 4);
  if (ifd0 > n - 2)
    return 0;
  cnt = g16 (t + ifd0);
  next = ifd0 + 2 + 12 * cnt;
  if (next > n - 4)
    return 0;
  ifd1 = g32 (t + next);
  if (ifd1 == 0 || ifd1 > n - 2)
    return 0;
  cnt = g16 (t + ifd1);
  if ((size_t) ifd1 + 2 + 12 * (size_t) cnt > n)
    return 0;
  for (i = 0; i < cnt; i++)
    {
      const unsigned char *e = t + ifd1 + 2 + 12 * i;
      uint32_t tag = g16 (e), type = g16 (e + 2);
      uint32_t val = type == 3 ? g16 (e + 8) : g32 (e + 8);
      if (tag == 0x0201)
	o = val;
      else if (tag == 0x0202)
	l = val;
    }
  if (o == 0 || l < 4 || o > n || l > n - o
      || t[o] != 0xFF || t[o + 1] != 0xD8)
    return 0;
  *off = o;
  *len = l;
  return 1;
}

/* Find the largest MPF "Large Thumbnail" image.  Offsets are relative
   to T (the MP endian field), as the MPF spec defines them.  */
static int
find_mpf_preview (const unsigned char *t, size_t n, size_t *off, size_t *len)
{
  uint32_t ifd, cnt, i, j, best_o = 0, best_l = 0;

  if (!tiff_header (t, n))
    return 0;
  ifd = g32 (t + 4);
  if (ifd > n - 2)
    return 0;
  cnt = g16 (t + ifd);
  if ((size_t) ifd + 2 + 12 * (size_t) cnt > n)
    return 0;
  for (i = 0; i < cnt; i++)
    {
      const unsigned char *e = t + ifd + 2 + 12 * i;
      uint32_t count, vo;
      if (g16 (e) != 0xB002)	/* MP Entry */
	continue;
      count = g32 (e + 4);
      vo = g32 (e + 8);
      if (vo > n || count > n - vo)
	return 0;
      for (j = 0; j + 16 <= count; j += 16)
	{
	  const unsigned char *m = t + vo + j;
	  uint32_t type = g32 (m) & 0xFFFFFF, size = g32 (m + 4),
	    o = g32 (m + 8);
	  if ((type == 0x010001 || type == 0x010002) && o != 0
	      && size > best_l)
	    {
	      best_o = o;
	      best_l = size;
	    }
	}
    }
  if (best_l == 0)
    return 0;
  *off = best_o;
  *len = best_l;
  return 1;
}

static int
write_all (const unsigned char *p, size_t n)
{
  return fwrite (p, 1, n, stdout) == n;
}

/* Copy LEN bytes at file position POS to stdout, checking for SOI.  */
static int
copy_range (FILE *f, long pos, size_t len)
{
  unsigned char buf[65536];
  int first = 1;
  struct stat st;

  /* Refuse ranges that run past the end of the file, so a lying MPF
     entry doesn't produce truncated output.  */
  if (fstat (fileno (f), &st) != 0 || pos < 0
      || (uintmax_t) pos + len > (uintmax_t) st.st_size)
    return 1;
  if (fseek (f, pos, SEEK_SET) != 0)
    return 1;
  while (len > 0)
    {
      size_t want = len < sizeof buf ? len : sizeof buf;
      size_t got = fread (buf, 1, want, f);
      if (got == 0)
	return 1;		/* truncated file */
      if (first)
	{
	  if (got < 2 || buf[0] != 0xFF || buf[1] != 0xD8)
	    return 1;
	  first = 0;
	}
      if (!write_all (buf, got))
	return 2;
      len -= got;
    }
  return fflush (stdout) == 0 ? 0 : 2;
}

int
main (int argc, char **argv)
{
  int want_preview;
  FILE *f;
  int c, m;
  unsigned char seg[65536];

  if (argc != 3)
    goto usage;
  if (strcmp (argv[1], "thumb") == 0)
    want_preview = 0;
  else if (strcmp (argv[1], "preview") == 0)
    want_preview = 1;
  else
    goto usage;

  f = fopen (argv[2], "rb");
  if (!f)
    {
      perror (argv[2]);
      return 2;
    }
  if (getc (f) != 0xFF || getc (f) != 0xD8)
    return 1;			/* not a JPEG */

  for (;;)
    {
      unsigned len, plen;
      long pos;

      if ((c = getc (f)) != 0xFF)
	return 1;
      do
	m = getc (f);
      while (m == 0xFF);	/* fill bytes */
      if (m == EOF || m == 0xDA || m == 0xD9)
	return 1;		/* start of scan / end: nothing found */
      if (m == 0x01 || (m >= 0xD0 && m <= 0xD7))
	continue;		/* markers without a length */
      if ((c = getc (f)) == EOF)
	return 1;
      len = (unsigned) c << 8;
      if ((c = getc (f)) == EOF)
	return 1;
      len |= (unsigned) c;
      if (len < 2)
	return 1;
      plen = len - 2;
      pos = ftell (f);		/* start of segment payload */

      if ((!want_preview && m == 0xE1) || (want_preview && m == 0xE2))
	{
	  size_t off, tlen;
	  if (fread (seg, 1, plen, f) != plen)
	    return 1;
	  if (!want_preview && plen >= 6 && memcmp (seg, "Exif\0\0", 6) == 0)
	    {
	      if (find_exif_thumb (seg + 6, plen - 6, &off, &tlen))
		{
		  if (!write_all (seg + 6 + off, tlen) || fflush (stdout))
		    return 2;
		  return 0;
		}
	      return 1;
	    }
	  if (want_preview && plen >= 4 && memcmp (seg, "MPF\0", 4) == 0)
	    {
	      if (find_mpf_preview (seg + 4, plen - 4, &off, &tlen))
		return copy_range (f, pos + 4 + (long) off, tlen);
	      return 1;
	    }
	}
      else if (fseek (f, pos + plen, SEEK_SET) != 0)
	return 1;
    }

 usage:
  fprintf (stderr, "Usage: %s thumb|preview FILE\n", argv[0]);
  return 2;
}
