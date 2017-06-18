#!/usr/bin/perl -wT
#
# Мурашев Андрей
# среда,  18 мая 2011 г. 14:42:16
# post_merch
#

=encoding utf8

=head1 Тестовое задание:

=over 4

=item

    Написать часть коннектора к платежной системе
    для переадресации клиента на адрес сервера платежной
    системы полученный в результате первого запроса.

##############################################################
# Основные обязательные параметры.
# Название             Длина/Тип    Описание

# client_orderid       12/Numeric   Идентификатор платежа в приложении клиента
# amount               10/Numeric   Сумма платежа. Дробная часть отделяется точкой.
# currency             3/String     Код валюты. Например: RUR
# order_desc           125/String   Краткое описание платежа
# redirect_url         128/String   URL, на который пользователь перенаправится после оплаты.
#                                   Вне зависимости от результата.
# ipaddress            20/String    Айпи плательщика
# control              40/String    Подпись параметров алгоритмом SHA-1. Описание приводится ниже.
# server_callback_url  128/String   Адрес, на который сервер передаст результат платежа после оплаты.
#                                   Подробно рассмотрен в разделе Коллбек. Параметр опциональный.
##############################################################
# Следующие параметры также являются обязательными, их наличие проверяется.
# Но если у вас нет возможности запрашивать их у пользователя, используйте
# постоянные значения, как, например, в этой таблице.

# Название         Длина/Тип      Значение            Описание
# country          2/String       RU                  Код страны покупателя
# city             50/String      Castle Rock         Город
# zip_code         10/String      000000              Почтовый код
# address1         50/String      Not specified       Адрес плательщика
# email            50/String      email@example.org   Адрес электронной почты плательщика
##############################################################

=cut

use strict;

use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use HTTP::Cookies;
use Digest::SHA1;

use CGI::Carp qw ( fatalsToBrowser );

my $EOL = "\015\012";
$EOL = "\n";    # переназначаем для консоли

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ####
# VALUES # VALUES # VALUES # VALUES # VALUES # VALUES # VALUES #
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ####
# Обязательные к заполнению переменные
my ( $client_orderid, $amount, $currency, $order_desc, $redirect_url, $ipaddress, $control,
  $server_callback_url, )
  = ( undef, undef, undef, undef, undef, undef, undef, undef, );

# Не обязательные к заполнению переменные,
# но без них ответ от сервера будет возвращен с ошибкой
my ( $country, $city, $zip_code, $address1, $email, ) = ( undef, undef, undef, undef, undef, );

# Секретные переменные
my $endpointid       = undef;
my $merchant_control = undef;

# Вспомогательный ХЕШ ,что б все было в кучке
my %reqOne = ();

# Переменные для формирования запроса
my ( $browser, $cookies, $response, $request, $url ) = ( undef, undef, undef, undef, undef, );

# Переменные для работы с ответом сервера
my $input    = undef;
my %post     = ();
my $location = undef;
#############################
# Формируем значения ХЕШа
#
%reqOne = (
  client_orderid      => 'Test-order',
  amount              => '3400',
  currency            => 'RUR',
  order_desc          => 'Order for perl test script',
  redirect_url        => 'http://example.org/',
  ipaddress           => '127.0.0.1',
  server_callback_url => 'http://example.org/',
  country             => 'RU',
  city                => 'Castle Rock',
  zip_code            => '000000',
  address1            => 'Not specified',
  email               => "email\@example.org",
  endpointid          => 00,
);

$reqOne{first_name} = 'Vasya';
$reqOne{last_name}  = 'Pupkin';

# url задается жестко
$url = 'https://example.org/api/v2/';
$url = "${url}sale-form/$reqOne{endpointid}";

# ключ для работы с системой
$merchant_control = '00000000-0000-0000-0000-000000000000';

# Формирование подписи строки состоит из:
# ENDPOINTID
# client_orderid
# amount (in cents)
# email
# merchant_control
#
# Шифруем строку запроса
#
### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1
$reqOne{control} = "$reqOne{endpointid}$reqOne{client_orderid}$reqOne{amount}$reqOne{email}$merchant_control";

my $sha1 = Digest::SHA1->new;
$sha1->add( $reqOne{control} );
$reqOne{control} = $sha1->clone->hexdigest;
### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1 ### SHA1
#while ( (my $k, my $v) = (each %reqOne) ) {
# print STDERR q|str: | . __LINE__ . ' ' . "$k => $v" ."\n"; }

# Формирование запроса к Серверу
# Создание coockie для дальнейщего
# использования(при необходимости)
# Определение параметров запроса
#
# создадим нового Агента пользователя
$browser = LWP::UserAgent->new( keep_alive => 1 );
$browser->conn_cache( LWP::ConnCache->new() );

# Создаем куки
$cookies = $browser->cookie_jar(
  HTTP::Cookies->new(
    'file'     => './cookies.lwp',
    'autosave' => 1
  )
);

# Маскируемся, выставляем время ожидания, пытаемся пройти через прокси
$browser->agent('Mozilla/4.0 (compatible; MSIE 5.12; Mac_PowerPC)');
$browser->timeout(5);
$browser->env_proxy;

# Если перенаправление, то это поможет
push @{ $browser->requests_redirectable }, 'POST';

# указываем тип контекста
$request = HTTP::Request->new( POST => $url );

### ### ###
# CONNECT
### ### ###
############################################
# WEB
# HTTP_REFERER: http://www.irkstroi.ru/ARIUS/post_merch.pl
# REQUEST_URI => /ARIUS/post_merch.pl
my %FORM = ();
my $form = undef;
$FORM{submit} = '';

my $http_ref = $ENV{HTTP_REFERER};
$http_ref = 'http://example.org' unless $http_ref;
my $host    = $ENV{HTTP_HOST};
my $reg_uri = $ENV{REQUEST_URI};

if ( "$http_ref" ne "http://$host$reg_uri" ) {
  print "Content-Type: text/html\n\n" unless @ARGV;
  print q|HTTP_REFERER: | . "$http_ref<br />\n";
  print q|HTTP_HOST/REQUEST_URI: | . "http://$host$reg_uri<br />\n";

  print &requestForm($form);
  print q|Переменные: | . "$_ => $ENV{$_}<br />\n" for ( keys %ENV );
} elsif ( "$http_ref" eq "http://$host$reg_uri" ) {

# Выполняем обработку кнопки "Отправить" - переадресовываем клиента на адрес,
# полученный от сервера после отправки ему первого запроса
  $FORM{submit} = 1;
} elsif ( "$http_ref" =~ "$url" ) {
  print "Content-Type: text/html\n\n" unless @ARGV;
  print q|HTTP_REFERER: | . "$http_ref<br />\n";
  print q|HTTP_HOST/REQUEST_URI: | . "http://$host$reg_uri<br />\n";

  # Делаем что нибдь ,если рефер пришел от сервера для
  # server_callback_url или redirect_url

} else {
  print "Content-Type: text/html\n\n" unless @ARGV;
  print q|Переменные: | . "$_ => $ENV{$_}<br />\n" for ( keys %ENV );
}

sub requestForm {

  my $form = <<MERCHANT_FORM;
  <form action="post_merch.pl" method=POST>
  <input type=hidden name=redirect-url value=''>
  <input type=submit value='Отправить'>
  </form>

MERCHANT_FORM

  return $form;
}

# В зависимости от выбранной кнопки
# выполняем те или иные действия
#
#if (0) {
if ( $FORM{submit} ) {
  $response = &requestOne( $request, \%reqOne, $url );

  # Ошибка, если статус не 1
  die "$url error: ", $response->status_line
    unless $response->is_success;

  # Ошибка, если тип возвращаемого контента не text/html
  die "Weird content type at $url -- ", $response->content_type
    unless $response->content_type eq 'text/html';
}

##########################################################################
# получаем ответ от сервера и обрабтываем
# а потом перенаправляем на него клиента
#
if ($response) {
  $input = $response->content;

  # Убираем %2F и подобное из строки ответа сервера
  &inputEscaped( $input, \%post );

  #print STDERR  q|str: | . __LINE__ . ' ' . $response->decoded_content. "\n" if ($response->decoded_content);

  # Создаем для удобства переменную - адрес перенаправления
  $location = "$post{'redirect-url'}" if ( $post{'redirect-url'} );

  # используем эту процедуру для преобразования
  # передаваемых символов кириллицы
  &StrEscaped($location);

  if ( $response->is_success ) {

    # Перенаправляем клиента на url, указанный в ответе сервера
    print "Location: $location\n\n";

  #print STDERR  q|str: | . __LINE__ . ' ' . $response->decoded_content. "\n" if ($response->decoded_content);
  } else {
    print STDERR q|str: | . __LINE__ . ' ' . $response->status_line, "\n";
  }

}

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### #
# FUNCTIONS # FUNCTIONS # FUNCTIONS # FUNCTIONS # FUNCTIONS #
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### #

=item

    Функция для формирования переменных запроса
    На входе:

=item *
    &requestOne($request, \%reqOne, $url);

=item *
    На выходе: return $response;

=cut

sub requestOne {
  my $request = $_[0];
  my $reqOne  = $_[1];
  my $url     = $_[2];

  # Отделяем последние два знака (копейки)
  ${$reqOne}{amount} =~ s|(\d?)([\d]{2})$|$1.$2|g;

  # Добавляем в запрос переменные
  $request = POST "$url", [ %{$reqOne} ];

  # Создаем объект запроса
  $response = $browser->request($request);

  return $response;
}

# вспомогательные процедуры
# Функция для разделения строки на параметр = значение
# и преобразования
#
sub inputEscaped {
  my $input = $_[0];
  my $post  = $_[1];

  my @pairs = split( /&/, $input );
  foreach my $pair (@pairs) {

    my ( $name, $value ) = split( /=/, $pair );
    $name =~ tr/+/ /;
    $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

    $value =~ tr/+/ /;
    $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    $value =~ tr/\'/\`/;#`

    ${$post}{$name} = $value;
  }

  return $post;
}

# используем эту процедуру для преобразования
# передаваемых символов кириллицы
#
sub StrEscaped {

  my ($str) = @_;
  $str =~ s/([^0-9A-Za-z\?&=:;])/sprintf("%%%x", ord($1))/eg;
  return $str;
}
