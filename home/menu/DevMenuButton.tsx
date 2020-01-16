import React from 'react';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { TouchableOpacity as TouchableOpacityGH } from 'react-native-gesture-handler';
import { Platform, StyleSheet, TouchableOpacity as TouchableOpacityRN, View } from 'react-native';

import { StyledView } from '../components/Views';
import { StyledText } from '../components/Text';

type Props = {
  buttonKey: string;
  label: string;
  onPress: (key: string) => any;
  icon?: string;
  withSeparator?: boolean;
  isEnabled?: boolean;
  detail?: string;
};

// When rendered inside bottom sheet, touchables from RN don't work on Android, but the ones from GH don't work on iOS.
const TouchableOpacity = Platform.OS === 'android' ? TouchableOpacityGH : TouchableOpacityRN;

const LabelNameOverrides = {
  'Reload JS Bundle': 'Reload JS Bundle only',
};

class DevMenuButton extends React.PureComponent<Props, any> {
  static defaultProps = {
    isEnabled: true,
  };

  state = {
    showDetails: true,
  };

  onPress = () => {
    if (this.props.onPress) {
      this.props.onPress(this.props.buttonKey);
    }
  };

  render() {
    const { label, icon, withSeparator, isEnabled, detail } = this.props;
    const { showDetails } = this.state;
    const normalizedLabel = LabelNameOverrides[label] || label;

    if (isEnabled) {
      const buttonStyles = withSeparator
        ? [styles.button, styles.buttonWithSeparator]
        : styles.button;

      return (
        <TouchableOpacity style={buttonStyles} onPress={this.onPress}>
          {icon && (
            <View style={styles.buttonIcon}>
              <MaterialCommunityIcons name={icon} size={20} color="#2F9BE4" />
            </View>
          )}
          <StyledText style={styles.buttonText} lightColor="#595c68">
            {normalizedLabel}
          </StyledText>
        </TouchableOpacity>
      );
    } else {
      return (
        <StyledView style={[styles.button, { flexDirection: 'column' }]}>
          <View style={{ flexDirection: 'row' }}>
            <View style={styles.buttonIcon} />
            <StyledText
              style={styles.buttonText}
              lightColor="#9ca0a6"
              darkColor="rgba(255,255,255,0.7)">
              {normalizedLabel}
            </StyledText>
          </View>
          {showDetails ? (
            <View style={{ flexDirection: 'row' }}>
              <View style={[styles.buttonIcon, { marginTop: -5, marginBottom: 15 }]} />
              <StyledText
                style={[
                  styles.buttonText,
                  {
                    marginTop: -5,
                    marginBottom: 15,
                    fontWeight: 'normal',
                    marginRight: 15,
                    flex: 1,
                  },
                ]}
                darkColor="rgba(255,255,255,0.7)"
                lightColor="#9ca0a6">
                {detail ? detail : 'Only available in development mode'}
              </StyledText>
            </View>
          ) : null}
        </StyledView>
      );
    }
  }
}

const styles = StyleSheet.create({
  button: {
    backgroundColor: 'transparent',
    flexDirection: 'row',
  },
  buttonWithSeparator: {
    borderBottomWidth: StyleSheet.hairlineWidth * 2,
  },
  buttonIcon: {
    marginVertical: 12,
    marginLeft: 20,
    alignSelf: 'center',
  },
  buttonText: {
    fontSize: 14,
    textAlign: 'left',
    marginVertical: 12,
    marginRight: 5,
    paddingHorizontal: 12,
    fontWeight: '700',
  },
});

export default DevMenuButton;
