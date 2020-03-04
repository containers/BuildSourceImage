Name:		BuildSourceImage
Version:	0.2
Release:	1%{?dist}
Summary:	Container Source Image tool

Group:		containers
License:	GPLv2
URL:		https://github.com/containers/BuildSourceImage
Source0:	BuildSourceImage.sh
Source1:	LICENSE
Source2:	README.md
Source3:	layout.md

#BuildRequires:	
Requires:	jq
Requires:	skopeo
Requires:	findutils
Requires:	file
%if 0%{?rhel} > 6
Requires:	yum-utils
%else
Requires:	dnf-command(download)
%endif

%description
%{summary}.

%prep


%build


%install
%{__mkdir_p} %{buildroot}/%{_bindir}
%{__mkdir_p} %{buildroot}/%{_defaultlicensedir}/%{name}
%{__mkdir_p} %{buildroot}/%{_defaultdocdir}/%{name}
%{__install} -T -m 0755 ${RPM_SOURCE_DIR}/BuildSourceImage.sh %{buildroot}/%{_bindir}/BuildSourceImage
%{__install} -T -m 0644 ${RPM_SOURCE_DIR}/LICENSE %{buildroot}/%{_defaultlicensedir}/%{name}/LICENSE
%{__install} -T -m 0644 ${RPM_SOURCE_DIR}/README.md %{buildroot}/%{_defaultdocdir}/%{name}/README.md
%{__install} -T -m 0644 ${RPM_SOURCE_DIR}/layout.md %{buildroot}/%{_defaultdocdir}/%{name}/layout.md


%files
%doc %{_defaultlicensedir}/%{name}/LICENSE
%doc %{_defaultdocdir}/%{name}/README.md
%doc %{_defaultdocdir}/%{name}/layout.md
%{_bindir}/BuildSourceImage



%changelog

