package APISchema::Generator::Markdown;
use strict;
use warnings;

# lib
use APISchema::Generator::Markdown::Formatter;
use APISchema::Generator::Markdown::ExampleFormatter;
use APISchema::Generator::Markdown::ResourceResolver;

# cpan
use Text::MicroTemplate::DataSection qw();

sub new {
    my ($class) = @_;

    my $renderer = Text::MicroTemplate::DataSection->new(
        escape_func => undef
    );
    bless {
        renderer => $renderer,
        map {
            ( $_ => $renderer->build_file($_) );
        } qw(index toc route resource request response
             request_example response_example),
    }, $class;
}

sub resolve_encoding ($) {
    my ($resources) = @_;
    $resources = { body => $resources } unless ref $resources;
    my $encoding = $resources->{encoding} // { '' => 'auto' };
    $encoding = { '' => $encoding } unless ref $encoding;
    return { %$resources, encoding => $encoding };
}

sub format_schema {
    my ($self, $schema) = @_;

    my $renderer = $self->{renderer};
    my $routes = $schema->get_routes;
    my $resources = $schema->get_resources;

    my $root = $schema->get_resource_root;
    my $resolver = APISchema::Generator::Markdown::ResourceResolver->new(
        schema => $root,
    );
    return $self->{index}->(
        $renderer,
        $schema,
        $self->{toc}->(
            $renderer,
            $routes,
            $resources,
        ),
        join('', map {
            my $route = $_;
            my $req = resolve_encoding($route->request_resource);
            my $request_resource = $route->canonical_request_resource($root);

            my $codes = do {
                my $res = $route->response_resource;
                $res = {} unless $res && ref $res;
                [ sort grep { $_ =~ qr!\A[0-9]+\z! } keys %$res ];
            };
            my $default_code = $codes->[0] // 200;
            my $response_resource = $route->canonical_response_resource($root, [
                $default_code
            ]);

            my $res = $_->response_resource;
            $res = scalar @$codes
                ? { map { $_ => resolve_encoding($res->{$_}) } @$codes }
                : { '' => resolve_encoding($res) };

            $self->{route}->(
                $renderer,
                $route,
                {
                    req =>  $self->{request_example}->(
                        $renderer,
                        $route,
                        APISchema::Generator::Markdown::ExampleFormatter->new(
                            resolver => $resolver,
                            spec     => $request_resource,
                        ),
                    ),
                    res => $self->{response_example}->(
                        $renderer,
                        $route,
                        $default_code,
                        APISchema::Generator::Markdown::ExampleFormatter->new(
                            resolver => $resolver,
                            spec     => $response_resource,
                        ),
                    ),
                },
                {
                    req => $self->{request}->($renderer, $route, $req),
                    res => join("\n", map {
                        $self->{response}->($renderer, $route, $_, $res->{$_});
                    } sort keys %$res),
                },
            );
        } @$routes),
        join('', map {
            my $properties = $resolver->properties($_->definition);
            $self->{resource}->($renderer, $resolver, $_, [ map { +{
                path => $_,
                definition => $properties->{$_},
            } } sort keys %$properties ]);
        } grep {
            ( $_->definition->{type} // '' ) ne 'hidden';
        } @$resources),
    );
}

1;
__DATA__
@@ index
? my ($schema, $toc_text, $routes_text, $resources_text) = @_;
# <?= $schema->title || '' ?>

?= $schema->description || ''

?= $toc_text

## <a name="routes"></a> Routes

?= $routes_text

## <a name="resources"></a> Resources

?= $resources_text

----------------------------------------------------------------
Generated by <?= __PACKAGE__ ?>

@@ toc
? my ($routes, $resources) = @_;

- [Routes](#routes)
? for (@$routes) {
    - [<?= $_->title ?>](#<?= anchor(route => $_->title) ?>) - <?= $_->method ?> <?= $_->route ?>
? }
- [Resources](#resources)
? for (@$resources) {
?   next if ( $_->definition->{type} // '' ) eq 'hidden';
    - [<?= $_->title ?>](#<?= anchor(resource => $_->title) ?>)
? }

@@ route
? my ($route, $example, $text) = @_;
### <a name="<?= anchor(route => $route) ?>"></a> <?= $route->title ?>

?= $example->{req}
?= $example->{res}
?= $route->description || ''

?= $text->{req}

?= $text->{res}

@@ request_example
? my ($route, $example) = @_;
```
<?= method($route->method) ?> <?= $route->route ?><?= $example->parameter ?><?= $example->header ?><?= $example->body ?>
```

@@ response_example
? my ($route, $code, $example) = @_;
```
HTTP/1.1 <?= http_status($code) ?><?= $example->header ?><?= $example->body ?>
```

@@ request
? my ($route, $req) = @_;
#### Request  <?= methods($route->method) ?>
?= $req->{description} // ''

? if (scalar grep { $req->{$_} } qw(header parameter body)) {
|Part|Resource|Content-Type|Encoding|
|----|--------|------------|--------|
?   for (qw(header parameter)) {
?     next unless $req->{$_};
|<?= $_ ?>|<?= type($req->{$_}) ?>|-|-|
?   } # for
?   if ($req->{body}) {
?     for (sort keys %{$req->{encoding}}) {
|body|<?= type($req->{body}) ?>|<?= content_type($_) ?>|<?= content_type($req->{encoding}->{$_}) ?>|
?     } # for
?   } # $req->{body}
? } # scalar keys %$req

@@ response
? my ($route, $code, $res) = @_;
#### Response <?= http_status_code($code) ?>
?= $res->{description} // ''

? if (scalar grep { $res->{$_} } qw(header parameter body)) {
|Part|Resource|Content-Type|Encoding|
|----|--------|------------|--------|
?   for (qw(header)) {
?     next unless $res->{$_};
|<?= $_ ?>|<?= type($res->{$_}) ?>|-|-|
?   } # for
?   if ($res->{body}) {
?     for (sort keys %{$res->{encoding}}) {
|body|<?= type($res->{body}) ?>|<?= content_type($_) ?>|<?= content_type($res->{encoding}->{$_}) ?>|
?     } # for
?   } # $res->{body}
? } # scalar keys %$res

@@ resource
? my ($r, $resource, $properties) = @_;
### <a name="<?= anchor(resource => $resource) ?>"></a> `<?= $resource->title ?>` : <?= type($resource->definition) ?>
```javascript
<?= pretty_json $r->example($resource->definition) ?>
```

?= $resource->definition->{description} || ''

#### Properties

? if (scalar @$properties) {
|Property|Type|Default|Example|Restrictions|Description|
|--------|----|-------|-------|------------|-----------|
?   for my $prop (@$properties) {
?     my $def = $prop->{definition};
|`<?= $prop->{path} ?>` |<?= type($def) ?> |<?= code($def->{default}) ?> |<?= code($def->{example}) ?> |<?= restriction($def) ?> |<?= desc($def->{description}) ?> |
?   } # $prop
? } # scalar @$properties

