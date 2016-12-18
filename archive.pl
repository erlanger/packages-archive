/*  Part of SWI-Prolog

    Author:        Jan Wielemaker and Matt Lilley
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2012-2016, VU University Amsterdam
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(archive,
          [ archive_open/3,             % +Stream, -Archive, +Options
            archive_open/4,             % +Stream, +Mode, -Archive, +Options
            archive_create/3,           % +OutputFile, +InputFileList, +Options
            archive_close/1,            % +Archive
            archive_property/2,         % +Archive, ?Property
            archive_next_header/2,      % +Archive, -Name
            archive_open_entry/2,       % +Archive, -EntryStream
            archive_header_property/2,  % +Archive, ?Property
            archive_set_header_property/2,      % +Archive, +Property
            archive_extract/3,          % +Archive, +Dir, +Options

            archive_entries/2,          % +Archive, -Entries
            archive_data_stream/3       % +Archive, -DataStream, +Options
          ]).
:- use_module(library(error)).
:- use_module(library(option)).
:- use_module(library(filesex)).

/** <module> Access several archive formats

This library uses _libarchive_ to access   a variety of archive formats.
The following example lists the entries in an archive:

  ==
  list_archive(File) :-
        archive_open(File, Archive, []),
        repeat,
           (   archive_next_header(Archive, Path)
           ->  format('~w~n', [Path]),
               fail
           ;   !,
               archive_close(Archive)
           ).
  ==

@see http://code.google.com/p/libarchive/
*/

:- use_foreign_library(foreign(archive4pl)).

archive_open(Stream, Archive, Options) :-
    archive_open(Stream, read, Archive, Options).

:- predicate_options(archive_open/4, 4,
                     [ close_parent(boolean),
                       filter(oneof([all,bzip2,compress,gzip,grzip,lrzip,
                                     lzip,lzma,lzop,none,rpm,uu,xz])),
                       format(oneof([all,'7zip',ar,cab,cpio,empty,gnutar,
                                     iso9660,lha,mtree,rar,raw,tar,xar,zip]))
                     ]).
:- predicate_options(archive_create/3, 3,
                     [ directory(atom),
                       pass_to(archive_open/4, 4)
                     ]).

%!  archive_open(+Data, +Mode, -Archive, +Options) is det.
%
%   Open the archive in Data and unify  Archive with a handle to the
%   opened archive. Data is either a file  or a stream that contains
%   a valid archive. Details are   controlled by Options. Typically,
%   the option close_parent(true) is used  to   close  stream if the
%   archive is closed using archive_close/1.  For other options, the
%   defaults are typically fine. The option format(raw) must be used
%   to process compressed  streams  that   do  not  contain explicit
%   entries (e.g., gzip'ed data)  unambibuously.   The  =raw= format
%   creates a _pseudo archive_ holding a single member named =data=.
%
%     * close_parent(+Boolean)
%     If this option is =true= (default =false=), Stream is closed
%     if archive_close/1 is called on Archive.
%
%     * compression(+Compression)
%     Synomym for filter(Compression).  Deprecated.
%
%     * filter(+Filter)
%     Support the indicated filter. This option may be
%     used multiple times to support multiple filters. In read mode,
%     If no filter options are provided, =all= is assumed. In write
%     mode, none is assumed.
%     Supported values are =all=, =bzip2=, =compress=, =gzip=,
%     =grzip=, =lrzip=, =lzip=, =lzma=, =lzop=, =none=, =rpm=, =uu=
%     and =xz=. The value =all= is default for read, =none= for write.
%
%     * format(+Format)
%     Support the indicated format.  This option may be used
%     multiple times to support multiple formats in read mode.
%     In write mode, you must supply a single format. If no format
%     options are provided, =all= is assumed for read mode. Note that
%     =all= does *not* include =raw=. To open both archive
%     and non-archive files, _both_ format(all) and
%     format(raw) must be specified. Supported values are: =all=,
%     =7zip=, =ar=, =cab=, =cpio=, =empty=, =gnutar=, =iso9660=,
%     =lha=, =mtree=, =rar=, =raw=, =tar=, =xar= and =zip=. The
%     value =all= is default for read.
%
%   Note that the actually supported   compression types and formats
%   may vary depending on the version   and  installation options of
%   the underlying libarchive  library.  This   predicate  raises  a
%   domain  error  if  the  (explicitly)  requested  format  is  not
%   supported.
%
%   @error  domain_error(filter, Filter) if the requested
%           filter is not supported.
%   @error  domain_error(format, Format) if the requested
%           format type is not supported.

archive_open(stream(Stream), Mode, Archive, Options) :-
    !,
    archive_open_stream(Stream, Mode, Archive, Options).
archive_open(Stream, Mode, Archive, Options) :-
    is_stream(Stream),
    !,
    archive_open_stream(Stream, Mode, Archive, Options).
archive_open(File, Mode, Archive, Options) :-
    open(File, Mode, Stream, [type(binary)]),
    catch(archive_open_stream(Stream, Mode, Archive, [close_parent(true)|Options]),
          E, (close(Stream, [force(true)]), throw(E))).


%!  archive_close(+Archive) is det.
%
%   Close the archive.  If  close_parent(true)   is  specified,  the
%   underlying stream is closed too.  If   there  is an entry opened
%   with  archive_open_entry/2,  actually  closing  the  archive  is
%   delayed until the stream associated with   the  entry is closed.
%   This can be used to open a   stream  to an archive entry without
%   having to worry about closing the archive:
%
%     ==
%     archive_open_named(ArchiveFile, EntryName, Stream) :-
%         archive_open(ArchiveFile, Handle, []),
%         archive_next_header(Handle, Name),
%         archive_open_entry(Handle, Stream),
%         archive_close(Archive).
%     ==


%!  archive_property(+Handle, ?Property) is nondet.
%
%   True when Property is a property  of the archive Handle. Defined
%   properties are:
%
%     * filters(List)
%     True when the indicated filters are applied before reaching
%     the archive format.

archive_property(Handle, Property) :-
    defined_archive_property(Property),
    Property =.. [Name,Value],
    archive_property(Handle, Name, Value).

defined_archive_property(filter(_)).


%!  archive_next_header(+Handle, -Name) is semidet.
%
%   Forward to the next entry of the  archive for which Name unifies
%   with the pathname of the entry. Fails   silently  if the name of
%   the  archive  is  reached  before  success.  Name  is  typically
%   specified if a  single  entry  must   be  accessed  and  unbound
%   otherwise. The following example opens  a   Prolog  stream  to a
%   given archive entry. Note that  _Stream_   must  be closed using
%   close/1 and the archive  must   be  closed using archive_close/1
%   after the data has been used.   See also setup_call_cleanup/3.
%
%     ==
%     open_archive_entry(ArchiveFile, Entry, Stream) :-
%         open(ArchiveFile, read, In, [type(binary)]),
%         archive_open(In, Archive, [close_parent(true)]),
%         archive_next_header(Archive, Entry),
%         archive_open_entry(Archive, Stream).
%     ==
%
%   @error permission_error(next_header, archive, Handle) if a
%   previously opened entry is not closed.

%!  archive_open_entry(+Archive, -Stream) is det.
%
%   Open the current entry as a stream. Stream must be closed.
%   If the stream is not closed before the next call to
%   archive_next_header/2, a permission error is raised.


%!  archive_set_header_property(+Archive, +Property)
%
%   Set Property of the current header.  Write-mode only. Defined
%   properties are:
%
%     * filetype(-Type)
%     Type is one of =file=, =link=, =socket=, =character_device=,
%     =block_device=, =directory= or =fifo=.  It appears that this
%     library can also return other values.  These are returned as
%     an integer.
%     * mtime(-Time)
%     True when entry was last modified at time.
%     * size(-Bytes)
%     True when entry is Bytes long.
%     * link_target(-Target)
%     Target for a link. Currently only supported for symbolic
%     links.

%!  archive_header_property(+Archive, ?Property)
%
%   True when Property is a property of the current header.  Defined
%   properties are:
%
%     * filetype(-Type)
%     Type is one of =file=, =link=, =socket=, =character_device=,
%     =block_device=, =directory= or =fifo=.  It appears that this
%     library can also return other values.  These are returned as
%     an integer.
%     * mtime(-Time)
%     True when entry was last modified at time.
%     * size(-Bytes)
%     True when entry is Bytes long.
%     * link_target(-Target)
%     Target for a link. Currently only supported for symbolic
%     links.
%     * format(-Format)
%     Provides the name of the archive format applicable to the
%     current entry.  The returned value is the lowercase version
%     of the output of archive_format_name().
%     * permissions(-Integer)
%     True when entry has the indicated permission mask.

archive_header_property(Archive, Property) :-
    (   nonvar(Property)
    ->  true
    ;   header_property(Property)
    ),
    archive_header_prop_(Archive, Property).

header_property(filetype(_)).
header_property(mtime(_)).
header_property(size(_)).
header_property(link_target(_)).
header_property(format(_)).
header_property(permissions(_)).


%!  archive_extract(+ArchiveFile, +Dir, +Options)
%
%   Extract files from the given archive into Dir. Supported
%   options:
%
%     * remove_prefix(+Prefix)
%     Strip Prefix from all entries before extracting
%
%   @error  existence_error(directory, Dir) if Dir does not exist
%           or is not a directory.
%   @error  domain_error(path_prefix(Prefix), Path) if a path in
%           the archive does not start with Prefix
%   @tbd    Add options

archive_extract(Archive, Dir, Options) :-
    (   exists_directory(Dir)
    ->  true
    ;   existence_error(directory, Dir)
    ),
    setup_call_cleanup(
        archive_open(Archive, Handle, Options),
        extract(Handle, Dir, Options),
        archive_close(Handle)).

extract(Archive, Dir, Options) :-
    archive_next_header(Archive, Path),
    !,
    (   archive_header_property(Archive, filetype(file))
    ->  archive_header_property(Archive, permissions(Perm)),
        (   option(remove_prefix(Remove), Options)
        ->  (   atom_concat(Remove, ExtractPath, Path)
            ->  true
            ;   domain_error(path_prefix(Remove), Path)
            )
        ;   ExtractPath = Path
        ),
        directory_file_path(Dir, ExtractPath, Target),
        file_directory_name(Target, FileDir),
        make_directory_path(FileDir),
        setup_call_cleanup(
            archive_open_entry(Archive, In),
            setup_call_cleanup(
                open(Target, write, Out, [type(binary)]),
                copy_stream_data(In, Out),
                close(Out)),
            close(In)),
        set_permissions(Perm, Target)
    ;   true
    ),
    extract(Archive, Dir, Options).
extract(_, _, _).

%!  set_permissions(+Perm:integer, +Target:atom)
%
%   Restore the permissions.  Currently only restores the executable
%   permission.

set_permissions(Perm, Target) :-
    Perm /\ 0o700 =\= 0,
    !,
    '$mark_executable'(Target).
set_permissions(_, _).


                 /*******************************
                 *    HIGH LEVEL PREDICATES     *
                 *******************************/

%!  archive_entries(+Archive, -Paths) is det.
%
%   True when Paths is a list of pathnames appearing in Archive.

archive_entries(Archive, Paths) :-
    setup_call_cleanup(
        archive_open(Archive, Handle, []),
        contents(Handle, Paths),
        archive_close(Handle)).

contents(Handle, [Path|T]) :-
    archive_next_header(Handle, Path),
    !,
    contents(Handle, T).
contents(_, []).

%!  archive_data_stream(+Archive, -DataStream, +Options) is nondet.
%
%   True when DataStream  is  a  stream   to  a  data  object inside
%   Archive.  This  predicate  transparently   unpacks  data  inside
%   _possibly nested_ archives, e.g., a _tar_   file  inside a _zip_
%   file. It applies the appropriate  decompression filters and thus
%   ensures that Prolog  reads  the   plain  data  from  DataStream.
%   DataStream must be closed after the  content has been processed.
%   Backtracking opens the next member of the (nested) archive. This
%   predicate processes the following options:
%
%     - meta_data(-Data:list(dict))
%     If provided, Data is unified with a list of filters applied to
%     the (nested) archive to open the current DataStream. The first
%     element describes the outermost archive. Each Data dict
%     contains the header properties (archive_header_property/2) as
%     well as the keys:
%
%       - filters(Filters:list(atom))
%       Filter list as obtained from archive_property/2
%       - name(Atom)
%       Name of the entry.
%
%   Note that this predicate can  handle   a  non-archive files as a
%   pseudo archive holding a single   stream by using archive_open/3
%   with the options `[format(all), format(raw)]`.

archive_data_stream(Archive, DataStream, Options) :-
    option(meta_data(MetaData), Options, _),
    archive_content(Archive, DataStream, MetaData, []).

archive_content(Archive, Entry, [EntryMetadata|PipeMetadataTail], PipeMetadata2) :-
    archive_property(Archive, filter(Filters)),
    repeat,
    (   archive_next_header(Archive, EntryName)
    ->  findall(EntryProperty,
                archive_header_property(Archive, EntryProperty),
                EntryProperties),
        dict_create(EntryMetadata, archive_meta_data,
                    [ filters(Filters),
                      name(EntryName)
                    | EntryProperties
                    ]),
        (   EntryMetadata.filetype == file
        ->  archive_open_entry(Archive, Entry0),
            (   EntryName == data,
                EntryMetadata.format == raw
            ->  % This is the last entry in this nested branch.
                % We therefore close the choicepoint created by repeat/0.
                % Not closing this choicepoint would cause
                % archive_next_header/2 to throw an exception.
                !,
                PipeMetadataTail = PipeMetadata2,
                Entry = Entry0
            ;   PipeMetadataTail = PipeMetadata1,
                open_substream(Entry0,
                               Entry,
                               PipeMetadata1,
                               PipeMetadata2)
            )
        ;   fail
        )
    ;   !,
        fail
    ).

open_substream(In, Entry, ArchiveMetadata, PipeTailMetadata) :-
    setup_call_cleanup(
        archive_open(stream(In),
                     Archive,
                     [ close_parent(true),
                       format(all),
                       format(raw)
                     ]),
        archive_content(Archive, Entry, ArchiveMetadata, PipeTailMetadata),
        archive_close(Archive)).


%!  archive_create(+OutputFile, +InputFiles, +Options) is det.
%
%   Convenience predicate to create an   archive  in OutputFile with
%   data from a list of InputFiles and the given Options.
%
%   Besides  options  supported  by  archive_open/4,  the  following
%   options are supported:
%
%     * directory(+Directory)
%     Changes the directory before adding input files. If this is
%     specified,   paths of  input  files   must   be relative to
%     Directory and archived files will not have Directory
%     as leading path. This is to simulate =|-C|= option of
%     the =tar= program.

archive_create(OutputFile, InputFiles, Options) :-
    must_be(list(text), InputFiles),
    option(directory(BaseDir), Options, '.'),
    setup_call_cleanup(
        archive_open(OutputFile, write, Archive, Options),
        archive_create_1(Archive, BaseDir, BaseDir, InputFiles, top),
        archive_close(Archive)).

archive_create_1(_, _, _, [], _) :- !.
archive_create_1(Archive, Base, Current, ['.'|Files], sub) :-
    !,
    archive_create_1(Archive, Base, Current, Files, sub).
archive_create_1(Archive, Base, Current, ['..'|Files], Where) :-
    !,
    archive_create_1(Archive, Base, Current, Files, Where).
archive_create_1(Archive, Base, Current, [File|Files], Where) :-
    directory_file_path(Current, File, Filename),
    archive_create_2(Archive, Base, Filename),
    archive_create_1(Archive, Base, Current, Files, Where).

archive_create_2(Archive, Base, Directory) :-
    exists_directory(Directory),
    !,
    entry_name(Base, Directory, Directory0),
    archive_next_header(Archive, Directory0),
    time_file(Directory, Time),
    archive_set_header_property(Archive, mtime(Time)),
    archive_set_header_property(Archive, filetype(directory)),
    archive_open_entry(Archive, EntryStream),
    close(EntryStream),
    directory_files(Directory, Files),
    archive_create_1(Archive, Base, Directory, Files, sub).
archive_create_2(Archive, Base, Filename) :-
    entry_name(Base, Filename, Filename0),
    archive_next_header(Archive, Filename0),
    size_file(Filename, Size),
    time_file(Filename, Time),
    archive_set_header_property(Archive, size(Size)),
    archive_set_header_property(Archive, mtime(Time)),
    setup_call_cleanup(
        archive_open_entry(Archive, EntryStream),
        setup_call_cleanup(
            open(Filename, read, DataStream, [type(binary)]),
            copy_stream_data(DataStream, EntryStream),
            close(DataStream)),
        close(EntryStream)).

entry_name('.', Name, Name) :- !.
entry_name(Base, Name, EntryName) :-
    directory_file_path(Base, EntryName, Name).
