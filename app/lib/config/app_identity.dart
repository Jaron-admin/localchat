/// Public installation identity. Internal package names remain compatible with upstream.
abstract final class AppIdentity {
  static const displayName = 'LocalChat';
  static const applicationId = 'io.github.jaronadmin.localchat';
  static const shareExtensionId = '$applicationId.ShareExtension';
  static const appleAppGroup = 'group.$applicationId';
  static const windowsMsixIdentity = 'JaronAdmin.LocalChat';
  static const windowsInstallerId = 'd635a531-59f6-4645-bd41-7b546c60ad8f';
  static const repositoryUrl = 'https://github.com/Jaron-admin/localchat';
  static const purchasesEnabled = false;
}
