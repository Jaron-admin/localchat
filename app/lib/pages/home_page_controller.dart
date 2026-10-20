import 'package:flutter/material.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum NearbySection { devices, send, receive }

class HomePageVm {
  final PageController controller;
  final HomeTab currentTab;
  final void Function(HomeTab) changeTab;
  final NearbySection nearbySection;

  HomePageVm({
    required this.controller,
    required this.currentTab,
    required this.changeTab,
    this.nearbySection = NearbySection.devices,
  });
}

final homePageControllerProvider = ReduxProvider<HomePageController, HomePageVm>(
  (ref) => HomePageController(returnToHome: () => ref.global.dispatch(NavigateAction.popUntilRoot())),
);

class HomePageController extends ReduxNotifier<HomePageVm> {
  final VoidCallback? returnToHome;
  HomePageController({this.returnToHome});
  @override
  HomePageVm init() {
    return HomePageVm(
      controller: PageController(),
      currentTab: HomeTab.chat,
      changeTab: (tab) => redux.dispatch(ChangeTabAction(tab)),
    );
  }
}

class ChangeTabAction extends ReduxAction<HomePageController, HomePageVm> {
  final HomeTab tab;

  ChangeTabAction(this.tab);

  @override
  HomePageVm reduce() {
    if (state.controller.hasClients) state.controller.jumpToPage(tab.index);
    return HomePageVm(
      controller: state.controller,
      currentTab: tab,
      changeTab: state.changeTab,
      nearbySection: state.nearbySection,
    );
  }
}

/// Sharing, drops and launch arguments all return to the existing homepage.
class OpenNearbyTransferAction extends ReduxAction<HomePageController, HomePageVm> {
  final NearbySection section;
  OpenNearbyTransferAction(this.section);
  @override
  HomePageVm reduce() {
    if (state.controller.hasClients) state.controller.jumpToPage(HomeTab.nearby.index);
    return HomePageVm(controller: state.controller, currentTab: HomeTab.nearby, changeTab: state.changeTab, nearbySection: section);
  }

  @override
  void after() => notifier.returnToHome?.call();
}
