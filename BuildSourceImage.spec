Name:		BuildSourceImage
Version:	0.2
Release:	1%{?dist}
Summary:	Container Source Image tool

Group:		containers
License:	GPLv2
URL:		https://github.com/containers/BuildSourceImage
Source0:	BuildSourceImage.sh

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
%{__install} -T -m 0755 ${RPM_SOURCE_DIR}/BuildSourceImage.sh %{buildroot}/%{_bindir}/BuildSourceImage


%files
%doc ${RPM_SOURCE_DIR}/LICENSE ${RPM_SOURCE_DIR}/README.md
%{_bindir}/BuildSourceImage



%changelog

