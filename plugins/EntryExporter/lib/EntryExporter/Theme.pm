package EntryExporter::Theme;
use strict;

use MT;
use MT::Entry;

sub condition {
    my ( $blog ) = @_;
    my $entry = MT->model('entry')->load({ blog_id => $blog->id }, { limit => 1 });
    return defined $entry ? 1 : 0;
}

sub template {
    my $app = shift;
    my ( $blog, $saved ) = @_;

    my @entries = MT->model('entry')->load({
        blog_id => $blog->id,
    });
    return unless scalar @entries;
    my @list;
    my %checked_ids;
    if ( $saved ) {
        %checked_ids = map { $_ => 1 } @{ $saved->{plugin_default_entries_export_ids} };
    }
    for my $entry ( @entries ) {
        push @list, {
            entry_title  => $entry->title,
            entry_id     => $entry->id,
            checked      => $saved ? $checked_ids{ $entry->id } : 1,
        };
    }
    my %param = ( entries => \@list );

    my $plugin = MT->component('EntryExporter');
    return $plugin->load_tmpl('export_entry.tmpl', \%param);
}

sub export {
    my ( $app, $blog, $settings ) = @_;
    my @entries;
    if ( defined $settings ) {
        my @ids = $settings->{plugin_default_entries_export_ids};
        @entries = MT->model('entry')->load({ id => \@ids });
    }
    else {
        @entries = MT->model('entry')->load({ blog_id => $blog->id });
    }
    return unless scalar @entries;

    my $data = {};
    for my $entry ( @entries ) {
        my $cats = $entry->categories;
        my @categories;
        for my $cat (@$cats) { push(@categories, $cat->basename); }
        my $hash = {
            title => $entry->title,
            text => $entry->text,
            text_more => $entry->text_more,
            excerpt => $entry->excerpt,
            keywords => $entry->keywords,
            convert_breaks => $entry->convert_breaks,
            status => $entry->status,
            authored_on => $entry->authored_on,
            created_on => $entry->created_on,
            modified_on => $entry->modified_on,
            allow_comments => $entry->allow_comments,
            allow_pings => $entry->allow_pings,
            tags  => join(',', $entry->get_tags),
            category  => join(',', @categories),
        };
        $data->{ $entry->basename } = $hash;
    }
    return %$data ? $data : undef;

}

sub import {
    my ( $element, $theme, $obj_to_apply ) = @_;
    my $entries = $element->{data};
    _add_entries( $theme, $obj_to_apply, $entries, 'entry' )
        or die "Failed to create theme default Entries";
    return 1;
}

sub _add_entries {
    my ( $theme, $blog, $entries, $class ) = @_;
    my $app = MT->instance;
    my @text_fields = qw(
        title   text     text_more
        excerpt keywords
    );
    for my $basename ( keys %$entries ) {
        my $entry = $entries->{$basename};
        next if MT->model($class)->count({
            basename => $basename,
            blog_id  => $blog->id,
        });
        next if MT->model($class)->count({
            title => $entry->{title},
            blog_id  => $blog->id,
        });
        my $obj = MT->model($class)->new();
        my $current_lang = MT->current_language;
        MT->set_language($blog->language);
        $obj->set_values({
            map { $_ => $theme->translate_templatized( $entry->{$_} ) }
            grep { exists $entry->{$_} }
            @text_fields
        });
        MT->set_language( $current_lang );

        $obj->basename( $basename );
        $obj->blog_id( $blog->id );
        $obj->author_id( $app->user->id );

        $obj->convert_breaks( $entry->{convert_breaks} );
        $obj->authored_on( $entry->{authored_on} );
        $obj->created_on( $entry->{created_on} );
        $obj->modified_on( $entry->{modified_on} );
        $obj->allow_comments( $entry->{allow_comments} );
        $obj->allow_pings( $entry->{allow_pings} );
        $obj->status(
            exists $entry->{status} ? $entry->{status} : MT::Entry::RELEASE()
        );
        if ( my $tags = $entry->{tags} ) {
            my @tags = ref $tags ? @$tags : split( /\s*\,\s*/, $tags );
            $obj->set_tags( @tags );
        }

        $obj->save or die $obj->errstr;

        my $cat_str;
        if ( $class eq 'entry' && ($cat_str = $entry->{category}) ) {
            my @cats = split( ',', $cat_str );

            my $primary = 1;
            while ( my $cat = shift @cats ) {
                my $c = MT::Category->load({ basename => $cat, blog_id => $blog->id });
                if(!$c) {
                    $c = create_category($blog->id, $cat);
                }

                my $place = MT->model('placement')->new;
                $place->set_values({
                    blog_id     => $blog->id,
                    entry_id    => $obj->id,
                    category_id => $c->id,
                    is_primary  => $primary,
                });
                $place->save;
                $primary = 0;
            }
        }
    }
    1;
}

sub create_category {
    my $blog_id = shift;
    my $category_label = shift;

    my $cat = MT::Category->new;
    $cat->blog_id($blog_id);
    $cat->label($category_label);
    $cat->save
      or die $cat->errstr;
    return $cat;
}

sub info {
    my ( $element, $theme, $blog ) = @_;
    my $data = $element->{data};
    my $plugin = MT->component('EntryExporter');
    return sub {
        $plugin->translate( 'Entries' ) .'('. MT->translate( '[_1] ', scalar keys %{$element->{data}} ) . $plugin->translate( 'entries' ). ')';
    };
}

1;
