# Statik

statik is a lightweight flexible text-based static blogging engine,
inspired by the venerable blosxom.

Posts are simple text files with headers, which are used to
generate static web pages (html, atom, etc.) to be served by a standard
webserver like apache or nginx.

No databases or dynamic web infrastructure are required, meaning you
can host your blog on a simple vps and still have it perform like a star
when you're slashdotted. The only real requirements are perl >= 5.06, and
the following perl modules from CPAN:

- Config::Tiny
- DateTime
- DateTime::Format::Strptime
- DateTime::Format::RFC3339
- Encode
- Exporter::Lite
- Hash::Merge
- JSON
- parent
- Text::MicroMason
- URI

Dynamic content, like comments and comment threads, are possible
with javascript.

