# work around a bug: https://rt.cpan.org/Ticket/Display.html?id=50991
sub s_form { return Lingua::EN::Conjugate::s_form(@_); }
