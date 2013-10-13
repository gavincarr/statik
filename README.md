# Statik

statik is a lightweight flexible text-based static blogging engine,
inspired by the venerable blosxom.

Posts are simple text files with headers, which are used to
generate static web pages (html, atom, etc.) to be served by a standard
webserver like apache or nginx.

No databases or dynamic web infrastructure are required, meaning you
can host your blog on a simple vps and still have it perform like a star
when you're slashdotted. The only real requirements are perl >= 5.10, and
a few perl modules from CPAN:

- parent
- Config::Tiny
- Encode
- Exporter::Lite
- JSON
- Hash::Merge
- Text::MicroMason
- Time::Piece
- URI

Dynamic content, like comments and comment threads, are possible
with javascript.

